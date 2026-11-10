import 'dart:typed_data';

Future<List<String>> getLastOcrWarnings() async => const [];

Future<String> recognizeImageText(Uint8List imageBytes) async {
  throw UnsupportedError('OCR não está disponível nesta plataforma.');
}
