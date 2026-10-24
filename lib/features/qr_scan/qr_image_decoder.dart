import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart' as zxing;

const int maxQrImageBytes = 20 * 1024 * 1024;

/// Decodes a QR Code from image bytes using the same implementation used by
/// the Web image-upload and drag-and-drop flows.
///
/// Throws [FormatException] for empty, oversized, unsupported, or unreadable
/// images so callers can show a recoverable message.
String decodeQrFromImageBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const FormatException('The image is empty.');
  }
  if (bytes.length > maxQrImageBytes) {
    throw const FormatException('The image exceeds the 20 MB limit.');
  }

  final decodedImage = img.decodeImage(bytes);
  if (decodedImage == null) {
    throw const FormatException('The image format is not supported.');
  }

  final orientedImage = img.bakeOrientation(decodedImage);
  final rgbaBytes = orientedImage
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.rgba);
  final pixels = Int32List(orientedImage.width * orientedImage.height);

  for (var pixelIndex = 0; pixelIndex < pixels.length; pixelIndex++) {
    final byteIndex = pixelIndex * 4;
    final red = rgbaBytes[byteIndex];
    final green = rgbaBytes[byteIndex + 1];
    final blue = rgbaBytes[byteIndex + 2];
    final alpha = rgbaBytes[byteIndex + 3];
    pixels[pixelIndex] = (alpha << 24) | (red << 16) | (green << 8) | blue;
  }

  final source = zxing.RGBLuminanceSource(
    orientedImage.width,
    orientedImage.height,
    pixels,
  );
  final bitmap = zxing.BinaryBitmap(zxing.GlobalHistogramBinarizer(source));
  try {
    return zxing.QRCodeReader().decode(bitmap).text;
  } on Object catch (error) {
    throw FormatException('No readable QR Code was found in the image.', error);
  }
}
