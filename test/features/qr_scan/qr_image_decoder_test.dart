import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';
import 'package:qr_ops/features/qr_scan/qr_image_decoder.dart';

void main() {
  group('decodeQrFromImageBytes', () {
    test('decodes an actual PNG QR image and preserves URL characters', () {
      const value = 'https://example.com/path?q=setor%201&tag=a+b#inicio';
      expect(decodeQrFromImageBytes(_qrImageBytes(value)), value);
    });

    test('decodes an actual JPEG QR image', () {
      const value = 'QR Ops JPEG fixture 123';
      final png = img.decodeImage(_qrImageBytes(value))!;
      final jpeg = img.encodeJpg(png, quality: 100);
      expect(decodeQrFromImageBytes(jpeg), value);
    });

    test('decodes a low-resolution QR image', () {
      const value = 'low-resolution-regression';
      expect(decodeQrFromImageBytes(_qrImageBytes(value, scale: 3)), value);
    });

    test('decodes a QR image with reduced contrast', () {
      const value = 'reduced-contrast-regression';
      expect(
        decodeQrFromImageBytes(
          _qrImageBytes(value, darkLevel: 75, lightLevel: 220),
        ),
        value,
      );
    });

    test('decodes a QR Code close to the image edges', () {
      const value = 'edge-regression';
      expect(decodeQrFromImageBytes(_qrImageBytes(value, quietZone: 1)), value);
    });

    test('decodes a QR image rotated by 90 degrees', () {
      const value = 'rotation-regression';
      final image = img.decodeImage(_qrImageBytes(value))!;
      final rotated = img.copyRotate(image, angle: 90);
      expect(decodeQrFromImageBytes(img.encodePng(rotated)), value);
    });

    test('rejects empty bytes', () {
      expect(
        () => decodeQrFromImageBytes(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid image bytes', () {
      expect(
        () => decodeQrFromImageBytes(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a valid image without a QR Code', () {
      final blank = img.Image(width: 80, height: 80);
      img.fill(blank, color: img.ColorRgb8(255, 255, 255));
      expect(
        () => decodeQrFromImageBytes(img.encodePng(blank)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects files larger than 20 MB before decoding', () {
      final oversized = Uint8List(maxQrImageBytes + 1);
      expect(
        () => decodeQrFromImageBytes(oversized),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Uint8List _qrImageBytes(
  String value, {
  int scale = 8,
  int quietZone = 4,
  int darkLevel = 0,
  int lightLevel = 255,
}) {
  final qrCode = QrCode(
    payload: QrPayload.fromString(value),
    errorCorrectLevel: QrErrorCorrectLevel.low,
  );
  final qr = QrImage(qrCode);
  final dimension = (qr.moduleCount + quietZone * 2) * scale;
  final canvas = img.Image(width: dimension, height: dimension);
  img.fill(canvas, color: img.ColorRgb8(lightLevel, lightLevel, lightLevel));

  for (var row = 0; row < qr.moduleCount; row++) {
    for (var column = 0; column < qr.moduleCount; column++) {
      if (!qr.isDark(row, column)) continue;
      for (var dy = 0; dy < scale; dy++) {
        for (var dx = 0; dx < scale; dx++) {
          canvas.setPixelRgb(
            (column + quietZone) * scale + dx,
            (row + quietZone) * scale + dy,
            0,
            0,
            0,
          );
        }
      }
    }
  }
  return img.encodePng(canvas);
}
