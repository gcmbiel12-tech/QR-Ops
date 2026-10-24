import 'dart:typed_data';

export 'qr_pdf_decoder_stub.dart'
    if (dart.library.js_interop) 'qr_pdf_decoder_web.dart';

typedef QrPdfDecodeResult = ({
  String value,
  int pageNumber,
  int totalPages,
  String imageBase64,
});
typedef QrPdfDecode = Future<List<QrPdfDecodeResult>> Function(
  Uint8List pdfBytes,
);
