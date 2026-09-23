import 'package:flutter/services.dart';

const _channel = MethodChannel('owned/text_reader');

/// Recognises printed text in an image file, on the device. Returns the lines
/// top to bottom, separated by newlines, or an empty string when there's none.
Future<String> recognizeText(String imagePath) async =>
    await _channel.invokeMethod<String>('recognize', {'path': imagePath}) ?? '';

/// Cuts the main subject out of a photo and places it on a clean white square, on the
/// device. Returns the new image's path, or null when nothing stands out or the phone
/// doesn't support it (iPhone needs iOS 17).
Future<String?> liftSubject(String imagePath) async {
  try {
    return await _channel.invokeMethod<String>('liftSubject', {
      'path': imagePath,
    });
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
