import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

import 'qr_visual_config.dart';
import 'qr_frame_painter.dart';

/// Composes the QR matrix, quiet zone, optional frame/call-to-action and logo
/// directly at the requested PNG dimensions (never upscales a small raster).
class QrPngExporter {
  const QrPngExporter();

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
    QrFrameStyle frame = QrFrameStyle.none,
    String? callToAction,
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
    if (contrastRatio(foreground, background) < 4.5) {
      throw ArgumentError('Use cores com contraste de pelo menos 4,5:1.');
    }

    final side = outputDimension.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(background, ui.BlendMode.src);

    final framed = frame != QrFrameStyle.none;
    final hasLabel =
        frame == QrFrameStyle.text &&
        (callToAction?.trim().isNotEmpty ?? false);
    final qrFraction = !framed
        ? 1.0
        : frame == QrFrameStyle.simple
        ? 0.78
        : 0.70;
    final codeBoxSide = side * qrFraction;
    final top = hasLabel ? side * 0.035 : (side - codeBoxSide) / 2;
    final codeRect = ui.Rect.fromLTWH(
      (side - codeBoxSide) / 2,
      top,
      codeBoxSide,
      codeBoxSide,
    );

    if (framed) paintQrFrame(canvas, ui.Size.square(side), frame, foreground);

    final modulePixels = codeBoxSide / moduleTotal;
    final matrixLeft = codeRect.left;
    final matrixTop = codeRect.top;
    final darkPaint = ui.Paint()
      ..color = foreground
      ..isAntiAlias = false;
    for (var row = 0; row < qrImage.moduleCount; row++) {
      for (var column = 0; column < qrImage.moduleCount; column++) {
        if (!qrImage.isDark(row, column)) continue;
        canvas.drawRect(
          ui.Rect.fromLTRB(
            matrixLeft + (column + quietZoneModules) * modulePixels,
            matrixTop + (row + quietZoneModules) * modulePixels,
            matrixLeft + (column + quietZoneModules + 1) * modulePixels,
            matrixTop + (row + quietZoneModules + 1) * modulePixels,
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

      final encodedSide = qrImage.moduleCount * modulePixels;
      final safeFraction = logoFraction.clamp(0.08, 0.14);
      final logoSide = encodedSide * safeFraction;
      final protectionSide = logoSide * 1.28;
      final center = ui.Offset(side / 2, codeRect.top + codeBoxSide / 2);
      final protection = ui.Rect.fromCenter(
        center: center,
        width: protectionSide,
        height: protectionSide,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          protection,
          ui.Radius.circular(protectionSide * 0.08),
        ),
        ui.Paint()..color = background,
      );

      final destination = ui.Rect.fromCenter(
        center: center,
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
      if (framed) {
        final label = (callToAction?.trim().isNotEmpty ?? false)
            ? callToAction!.trim()
            : frame.defaultCallToAction;
        if (label.isNotEmpty) {
          final builder =
              ui.ParagraphBuilder(
                  ui.ParagraphStyle(
                    textAlign: ui.TextAlign.center,
                    maxLines: 1,
                    ellipsis: '…',
                  ),
                )
                ..pushStyle(
                  ui.TextStyle(
                    color: foreground,
                    fontSize: (side * 0.047).clamp(10.0, 76.0),
                    fontWeight: ui.FontWeight.w700,
                  ),
                )
                ..addText(label);
          final paragraph = builder.build()
            ..layout(ui.ParagraphConstraints(width: side * 0.84));
          canvas.drawParagraph(paragraph, ui.Offset(side * 0.08, side * 0.83));
        }
      }

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
