import 'dart:typed_data';

export 'ocr_pdf_stub.dart' if (dart.library.js_interop) 'ocr_pdf_web.dart';

typedef OcrRecognizePdf = Future<String> Function(Uint8List pdfBytes);
