import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('qrOpsRecognizePdf')
external JSPromise<JSString> _recognizePdf(JSString base64Pdf);

const int maxOcrPdfBytes = 100 * 1024 * 1024;

Future<String> recognizePdfText(Uint8List pdfBytes) async {
  if (pdfBytes.isEmpty) throw ArgumentError('O PDF está vazio.');
  if (pdfBytes.length > maxOcrPdfBytes) {
    throw ArgumentError('O PDF excede o limite de 100 MB.');
  }
  try {
    return (await _recognizePdf(base64Encode(pdfBytes).toJS).toDart).toDart;
  } on Object catch (error) {
    throw StateError('Falha na leitura do PDF no navegador: $error');
  }
}
