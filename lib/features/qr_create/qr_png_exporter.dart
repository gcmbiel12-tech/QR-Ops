import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:qr/qr.dart';

/// Renders the existing QR matrix as an 8-bit-per-module PNG with a four-
/// module quiet zone. Output dimensions scale with the QR version.
class QrPngExporter {
  const QrPngExporter();

  static const pixelsPerModule = 8;
  static const quietZoneModules = 4;

  Future<Uint8List> export(QrImage qrImage) async {
    final moduleTotal = qrImage.moduleCount + quietZoneModules * 2;
    final dimension = moduleTotal * pixelsPerModule;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);

    final darkPaint = ui.Paint()
      ..color = const ui.Color(0xFF000000)
      ..isAntiAlias = false;

    for (var row = 0; row < qrImage.moduleCount; row++) {
      for (var column = 0; column < qrImage.moduleCount; column++) {
        if (!qrImage.isDark(row, column)) continue;

        canvas.drawRect(
          ui.Rect.fromLTWH(
            (column + quietZoneModules) * pixelsPerModule.toDouble(),
            (row + quietZoneModules) * pixelsPerModule.toDouble(),
            pixelsPerModule.toDouble(),
            pixelsPerModule.toDouble(),
          ),
          darkPaint,
        );
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(dimension, dimension);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('Não foi possível codificar o PNG.');
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}
