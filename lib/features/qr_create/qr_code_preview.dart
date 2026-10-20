import 'package:flutter/material.dart';
import 'package:qr/qr.dart' as qr;

class QrCodePreview extends StatelessWidget {
  const QrCodePreview({
    super.key,
    required this.image,
    this.size = 240,
    this.foreground = Colors.black,
    this.background = Colors.white,
  });

  final qr.QrImage image;
  final double size;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Prévia do QR Code',
      child: CustomPaint(
        key: const ValueKey('qr-preview'),
        size: Size.square(size),
        painter: _QrCodePainter(image, foreground, background),
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
