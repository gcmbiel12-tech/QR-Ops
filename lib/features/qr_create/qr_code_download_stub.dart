import 'dart:typed_data';

Future<void> downloadQrCodePng(
  Uint8List bytes, {
  required String filename,
}) async {
  throw UnsupportedError('O download de PNG está disponível na versão Web.');
}
