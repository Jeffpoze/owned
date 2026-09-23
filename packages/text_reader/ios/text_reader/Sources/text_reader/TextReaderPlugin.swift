import Flutter
import UIKit
import Vision

/// On-device vision with Apple's Vision framework: reads printed text from an image
/// file, and cuts the main subject out of a photo onto a clean white background.
public class TextReaderPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "owned/text_reader", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(TextReaderPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "liftSubject" {
      liftSubject(call, result: result)
      return
    }
    guard call.method == "recognize",
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage else {
      result(FlutterError(code: "bad_image", message: "Couldn't open the image.", details: nil))
      return
    }

    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "recognition_failed", message: error.localizedDescription, details: nil))
        }
        return
      }
      let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
      let lines = TextReaderPlugin.rows(observations)
      DispatchQueue.main.async { result(lines.joined(separator: "\n")) }
    }
    request.recognitionLevel = .accurate
    // Model and serial numbers aren't words: don't "correct" them.
    request.usesLanguageCorrection = false

    let orientation = CGImagePropertyOrientation(image.imageOrientation)
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:]).perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "recognition_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

extension TextReaderPlugin {
  /// Cuts the photo's subject out and centres it on a white square, saved as a JPEG in the
  /// temporary folder. Returns its path, or nil when nothing stands out or the phone can't
  /// do it (needs iOS 17).
  func liftSubject(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          let image = UIImage(contentsOfFile: path),
          let cgImage = image.cgImage else {
      result(FlutterError(code: "bad_image", message: "Couldn't open the image.", details: nil))
      return
    }
    guard #available(iOS 17.0, *) else {
      result(nil)
      return
    }
    let orientation = CGImagePropertyOrientation(image.imageOrientation)
    DispatchQueue.global(qos: .userInitiated).async {
      let done: (Any?) -> Void = { value in DispatchQueue.main.async { result(value) } }
      do {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
          return done(nil)
        }
        let buffer = try observation.generateMaskedImage(
          ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cut = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return done(nil) }

        // White square with a margin, subject centred: reads like a catalog photo.
        let w = CGFloat(cut.width), h = CGFloat(cut.height)
        let side = max(w, h) * 1.15
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
          UIColor.white.setFill()
          ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
          UIImage(cgImage: cut).draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.9) else { return done(nil) }
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent("lifted_\(UUID().uuidString).jpg")
        try data.write(to: out)
        done(out.path)
      } catch {
        // Nothing recognisable, or not supported on this device (e.g. the simulator).
        done(nil)
      }
    }
  }

  /// Joins pieces of text that sit on the same printed row (a receipt's item on the left
  /// and its price on the right), then orders rows top to bottom.
  static func rows(_ observations: [VNRecognizedTextObservation]) -> [String] {
    // Vision's y axis points up, so higher midY means nearer the top.
    let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    var rows: [[VNRecognizedTextObservation]] = []
    for o in sorted {
      if let last = rows.last?.last,
         abs(last.boundingBox.midY - o.boundingBox.midY) < min(last.boundingBox.height, o.boundingBox.height) * 0.5 {
        rows[rows.count - 1].append(o)
      } else {
        rows.append([o])
      }
    }
    return rows.map { row in
      row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "  ")
    }
  }
}

extension CGImagePropertyOrientation {
  init(_ o: UIImage.Orientation) {
    switch o {
    case .up: self = .up
    case .down: self = .down
    case .left: self = .left
    case .right: self = .right
    case .upMirrored: self = .upMirrored
    case .downMirrored: self = .downMirrored
    case .leftMirrored: self = .leftMirrored
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
