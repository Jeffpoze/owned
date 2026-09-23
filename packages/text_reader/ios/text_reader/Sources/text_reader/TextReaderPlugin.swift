import Flutter
import UIKit
import Vision

/// Reads printed text from an image file with Apple's Vision framework, on the device.
public class TextReaderPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "owned/text_reader", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(TextReaderPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
