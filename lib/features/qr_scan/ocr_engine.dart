import 'dart:typed_data';

export 'ocr_engine_stub.dart'
    if (dart.library.io) 'ocr_engine_native.dart'
    if (dart.library.js_interop) 'ocr_engine_web.dart';

typedef OcrRecognizeImage = Future<String> Function(Uint8List imageBytes);
