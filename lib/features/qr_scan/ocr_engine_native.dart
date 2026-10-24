import 'dart:typed_data';

import 'package:flutter_ocr_native/flutter_ocr_native.dart';

Future<String> recognizeImageText(Uint8List imageBytes) async {
  final reader = OcrReader();
  try {
    final result = await reader.readFromBytes(imageBytes);
    return result.text;
  } finally {
    await reader.dispose();
  }
}
