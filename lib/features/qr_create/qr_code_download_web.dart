import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> downloadQrCodePng(Uint8List bytes, {required String filename}) =>
    _downloadFile(bytes, filename, 'image/png');

Future<void> downloadQrCodePdf(Uint8List bytes, {required String filename}) =>
    _downloadFile(bytes, filename, 'application/pdf');

Future<void> _downloadFile(
  Uint8List bytes,
  String filename,
  String contentType,
) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: contentType),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = objectUrl
    ..download = filename
    ..style.display = 'none';

  final body = web.document.body;
  if (body == null) {
    throw StateError('O navegador não disponibilizou a página.');
  }

  body.append(anchor);
  try {
    anchor.click();
  } finally {
    anchor.remove();
    Timer(const Duration(seconds: 1), () {
      web.URL.revokeObjectURL(objectUrl);
    });
  }
}
