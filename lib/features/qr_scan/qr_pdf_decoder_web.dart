import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'qr_pdf_decoder.dart';

@JS('qrOpsScanPdfForQr')
external JSPromise<JSString> _scanPdfForQr(JSString base64Pdf);

Future<List<QrPdfDecodeResult>> decodeQrFromPdfBytes(Uint8List pdfBytes) async {
  if (pdfBytes.isEmpty) throw ArgumentError('O PDF está vazio.');
  if (pdfBytes.length > 20 * 1024 * 1024) {
    throw ArgumentError('O PDF excede o limite de 20 MB.');
  }
  try {
    final raw = (await _scanPdfForQr(
      base64Encode(pdfBytes).toJS,
    ).toDart).toDart;
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) {
          final entry = item as Map<String, dynamic>;
          return (
            value: entry['value'] as String,
            pageNumber: entry['pageNumber'] as int,
            totalPages: entry['totalPages'] as int,
            imageBase64: entry['imageBase64'] as String? ?? '',
          );
        })
        .toList(growable: false);
  } on Object catch (error) {
    throw StateError('Falha ao procurar QR Codes no PDF: $error');
  }
}
