import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr/qr.dart' as qr;

import 'qr_png_exporter.dart';
import 'qr_visual_config.dart';
import 'qr_frame_painter.dart';

class QrCodePreview extends StatelessWidget {
  const QrCodePreview({
    super.key,
    required this.image,
    this.size = 280,
    this.foreground = Colors.black,
    this.background = Colors.white,
    this.logoBytes,
    this.logoFraction = 0.12,
    this.frame = QrFrameStyle.none,
    this.callToAction,
  });

  final qr.QrImage image;
  final double size;
  final Color foreground;
  final Color background;
  final Uint8List? logoBytes;
  final double logoFraction;
  final QrFrameStyle frame;
  final String? callToAction;

  @override
  Widget build(BuildContext context) {
    final framed = frame != QrFrameStyle.none;
    final hasLabel =
        frame == QrFrameStyle.text &&
        (callToAction?.trim().isNotEmpty ?? false);
    final qrFraction = !framed
        ? 1.0
        : frame == QrFrameStyle.simple
        ? 0.78
        : 0.70;
    final codeBoxSide = size * qrFraction;
    final top = hasLabel ? size * 0.035 : (size - codeBoxSide) / 2;
    final logoSide =
        (codeBoxSide *
            image.moduleCount /
            (image.moduleCount + QrPngExporter.quietZoneModules * 2)) *
        logoFraction.clamp(0.08, 0.14);
    final protectionSide = logoSide * 1.28;
    final logoTop = top + codeBoxSide / 2 - protectionSide / 2;

    return Semantics(
      label: 'Prévia do QR Code',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            CustomPaint(
              key: const ValueKey('qr-preview'),
              size: Size.square(size),
              painter: _QrCompositionPainter(
                image: image,
                foreground: foreground,
                background: background,
                frame: frame,
                callToAction: callToAction,
              ),
            ),
            Positioned(
              left: (size - protectionSide) / 2,
              top: logoTop,
              width: protectionSide,
              height: protectionSide,
              child: Container(
                padding: EdgeInsets.all(logoSide * 0.14),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(protectionSide * 0.08),
                ),
                child: logoBytes == null
                    ? Image.asset('web/icons/Icon-512.png', fit: BoxFit.contain)
                    : Image.memory(logoBytes!, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrCompositionPainter extends CustomPainter {
  const _QrCompositionPainter({
    required this.image,
    required this.foreground,
    required this.background,
    required this.frame,
    required this.callToAction,
  });

  final qr.QrImage image;
  final Color foreground;
  final Color background;
  final QrFrameStyle frame;
  final String? callToAction;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
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
    final codeRect = Rect.fromLTWH(
      (side - codeBoxSide) / 2,
      top,
      codeBoxSide,
      codeBoxSide,
    );

    if (framed) paintQrFrame(canvas, size, frame, foreground);

    final moduleTotal = image.moduleCount + QrPngExporter.quietZoneModules * 2;
    final moduleSize = codeBoxSide / moduleTotal;
    final darkPaint = Paint()
      ..color = foreground
      ..isAntiAlias = false;
    for (var row = 0; row < image.moduleCount; row++) {
      for (var column = 0; column < image.moduleCount; column++) {
        if (!image.isDark(row, column)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            codeRect.left +
                (column + QrPngExporter.quietZoneModules) * moduleSize,
            codeRect.top + (row + QrPngExporter.quietZoneModules) * moduleSize,
            moduleSize,
            moduleSize,
          ),
          darkPaint,
        );
      }
    }

    if (framed) {
      final label = (callToAction?.trim().isNotEmpty ?? false)
          ? callToAction!.trim()
          : frame.defaultCallToAction;
      if (label.isNotEmpty) {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: foreground,
              fontSize: (side * 0.047).clamp(10.0, 76.0),
              fontWeight: FontWeight.w700,
            ),
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: side * 0.84);
        painter.paint(canvas, Offset((side - painter.width) / 2, side * 0.83));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrCompositionPainter oldDelegate) =>
      !identical(oldDelegate.image, image) ||
      oldDelegate.foreground != foreground ||
      oldDelegate.background != background ||
      oldDelegate.frame != frame ||
      oldDelegate.callToAction != callToAction;
}
