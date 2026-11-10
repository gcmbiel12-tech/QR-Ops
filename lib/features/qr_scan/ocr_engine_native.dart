import 'dart:typed_data';

import 'package:flutter_ocr_native/flutter_ocr_native.dart';

List<String> _lastOcrWarnings = const [];

Future<List<String>> getLastOcrWarnings() async => _lastOcrWarnings;

Future<String> recognizeImageText(Uint8List imageBytes) async {
  final reader = OcrReader();
  try {
    final result = await reader.readFromBytes(imageBytes);
    _lastOcrWarnings = result.blocks
        .expand((block) => block.lines)
        .where((line) => line.confidence != null && line.confidence! < 0.65)
        .map((line) => line.text.trim())
        .where((line) => line.isNotEmpty)
        .toSet()
        .take(20)
        .toList();
    return result.text;
  } finally {
    await reader.dispose();
  }
}
