import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('qrOpsRecognizeImage')
external JSPromise<JSString> _recognizeImage(JSString imageDataUrl);

Future<String> recognizeImageText(Uint8List imageBytes) async {
  if (imageBytes.isEmpty) throw ArgumentError('A imagem está vazia.');
  final encoded = base64Encode(imageBytes);
  final isPng =
      imageBytes.length >= 8 &&
      imageBytes[0] == 0x89 &&
      imageBytes[1] == 0x50 &&
      imageBytes[2] == 0x4e &&
      imageBytes[3] == 0x47;
  final isWebp =
      imageBytes.length >= 12 &&
      imageBytes[0] == 0x52 &&
      imageBytes[1] == 0x49 &&
      imageBytes[2] == 0x46 &&
      imageBytes[3] == 0x46 &&
      imageBytes[8] == 0x57 &&
      imageBytes[9] == 0x45 &&
      imageBytes[10] == 0x42 &&
      imageBytes[11] == 0x50;
  final mimeType = isPng
      ? 'image/png'
      : isWebp
      ? 'image/webp'
      : 'image/jpeg';
  final dataUrl = 'data:$mimeType;base64,$encoded';
  try {
    return (await _recognizeImage(dataUrl.toJS).toDart).toDart;
  } on Object catch (error) {
    throw StateError('Falha no OCR local do navegador: $error');
  }
}
