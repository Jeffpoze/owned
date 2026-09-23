import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:text_reader/text_reader.dart';

import '../domain/label_parser.dart';
import '../domain/receipt_parser.dart';

/// Reads a photo of a product label on the device: the printed text (Apple Vision
/// on iOS, Google ML Kit on Android) and any barcodes in the picture.
/// Nothing leaves the phone.
Future<LabelFields> readLabelPhoto(String imagePath) async {
  final scanner = MobileScannerController(autoStart: false);
  try {
    final results = await Future.wait([
      recognizeText(imagePath).catchError((_) => ''),
      scanner
          .analyzeImage(imagePath)
          .then((c) => c?.barcodes ?? const <Barcode>[])
          .catchError((_) => const <Barcode>[]),
    ]);
    final text = results[0] as String;
    final barcodes = [
      for (final b in results[1] as List<Barcode>)
        if (b.rawValue != null && b.rawValue!.trim().isNotEmpty)
          b.rawValue!.trim(),
    ];
    return parseLabel(text, barcodes: barcodes);
  } finally {
    await scanner.dispose();
  }
}

/// Reads a photo of a receipt on the device.
Future<ReceiptFields> readReceiptPhoto(String imagePath) async =>
    parseReceipt(await recognizeText(imagePath).catchError((_) => ''));
