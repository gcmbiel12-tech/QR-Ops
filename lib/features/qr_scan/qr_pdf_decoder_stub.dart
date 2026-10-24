import 'dart:typed_data';

import 'qr_pdf_decoder.dart';

Future<List<QrPdfDecodeResult>> decodeQrFromPdfBytes(Uint8List pdfBytes) async {
  throw UnsupportedError(
    'A leitura de QR Codes em PDF está disponível apenas na versão Web do QR Ops.',
  );
}
