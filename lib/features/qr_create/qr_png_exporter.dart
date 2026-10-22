import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

/// Renders the QR matrix directly at the requested square PNG dimensions.
class QrPngExporter {
  const QrPngExporter();

  /// Kept for compatibility with existing tests and callers.
  static const pixelsPerModule = 8;
  static const quietZoneModules = 4;
  static const logoAsset = 'web/icons/Icon-512.png';

  Future<Uint8List> export(
    QrImage qrImage, {
    int? dimension,
    ui.Color foreground = const ui.Color(0xFF000000),
    ui.Color background = const ui.Color(0xFFFFFFFF),
    Uint8List? logoBytes,
    double logoFraction = 0.12,
  }) async {
    final moduleTotal = qrImage.moduleCount + quietZoneModules * 2;
    final outputDimension = dimension ?? moduleTotal * pixelsPerModule;
    if (dimension != null &&
        !const [256, 512, 1024, 2048].contains(dimension)) {
      throw ArgumentError.value(
        dimension,
        'dimension',
        'Resolução não suportada.',
      );
    }

    final modulePixels = outputDimension / moduleTotal;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(background, ui.BlendMode.src);
    final darkPaint = ui.Paint()
      ..color = foreground
      ..isAntiAlias = false;

    for (var row = 0; row < qrImage.moduleCount; row++) {
      for (var column = 0; column < qrImage.moduleCount; column++) {
        if (!qrImage.isDark(row, column)) continue;
        canvas.drawRect(
          ui.Rect.fromLTRB(
            (column + quietZoneModules) * modulePixels,
            (row + quietZoneModules) * modulePixels,
            (column + quietZoneModules + 1) * modulePixels,
            (row + quietZoneModules + 1) * modulePixels,
          ),
          darkPaint,
        );
      }
    }

    ui.Image? logo;
    try {
      final bytes =
          logoBytes ?? (await rootBundle.load(logoAsset)).buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        logo = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }

      // Keep the logo and its white protection well inside the encoded area.
      final codeSide = qrImage.moduleCount * modulePixels;
      final safeFraction = logoFraction.clamp(0.08, 0.14);
      final logoSide = codeSide * safeFraction;
      final protectionSide = logoSide * 1.28;
      final center = outputDimension / 2;
      final protection = ui.Rect.fromCenter(
        center: ui.Offset(center, center),
        width: protectionSide,
        height: protectionSide,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          protection,
          ui.Radius.circular(protectionSide * 0.08),
        ),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );

      final destination = ui.Rect.fromCenter(
        center: ui.Offset(center, center),
        width: logoSide,
        height: logoSide,
      );
      final sourceSide = logo.width < logo.height
          ? logo.width.toDouble()
          : logo.height.toDouble();
      final source = ui.Rect.fromLTWH(
        (logo.width - sourceSide) / 2,
        (logo.height - sourceSide) / 2,
        sourceSide,
        sourceSide,
      );
      canvas.drawImageRect(
        logo,
        source,
        destination,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
    } finally {
      final picture = recorder.endRecording();
      final image = await picture.toImage(outputDimension, outputDimension);
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw StateError('Não foi possível codificar o PNG.');
        return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      } finally {
        image.dispose();
        picture.dispose();
        logo?.dispose();
      }
    }
  }
}
