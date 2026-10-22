import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr/qr.dart' as qr;

class QrCodePreview extends StatelessWidget {
  const QrCodePreview({
    super.key,
    required this.image,
    this.size = 240,
    this.foreground = Colors.black,
    this.background = Colors.white,
    this.logoBytes,
    this.logoFraction = 0.12,
  });

  final qr.QrImage image;
  final double size;
  final Color foreground;
  final Color background;
  final Uint8List? logoBytes;
  final double logoFraction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Prévia do QR Code',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              key: const ValueKey('qr-preview'),
              size: Size.square(size),
              painter: _QrCodePainter(image, foreground, background),
            ),
            Container(
              width: size * logoFraction * 1.28,
              height: size * logoFraction * 1.28,
              padding: EdgeInsets.all(size * logoFraction * 0.08),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(size * 0.012),
              ),
              child: logoBytes == null
                  ? Image.asset('web/icons/Icon-512.png', fit: BoxFit.contain)
                  : Image.memory(logoBytes!, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrCodePainter extends CustomPainter {
  const _QrCodePainter(this.image, this.foreground, this.background);

  final qr.QrImage image;
  final Color foreground;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final moduleSize = side / (image.moduleCount + 8);
    final inset = (side - image.moduleCount * moduleSize) / 2;

    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final darkPaint = Paint()..color = foreground;

    for (var row = 0; row < image.moduleCount; row++) {
      for (var column = 0; column < image.moduleCount; column++) {
        if (image.isDark(row, column)) {
          canvas.drawRect(
            Rect.fromLTWH(
              inset + column * moduleSize,
              inset + row * moduleSize,
              moduleSize,
              moduleSize,
            ),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrCodePainter oldDelegate) =>
      !identical(oldDelegate.image, image) ||
      oldDelegate.foreground != foreground ||
      oldDelegate.background != background;
}
