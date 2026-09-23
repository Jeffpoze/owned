import 'package:flutter/services.dart';

const _channel = MethodChannel('owned/text_reader');

/// Recognises printed text in an image file, on the device. Returns the lines
/// top to bottom, separated by newlines, or an empty string when there's none.
Future<String> recognizeText(String imagePath) async =>
    await _channel.invokeMethod<String>('recognize', {'path': imagePath}) ?? '';
