import 'dart:math' as math;
import 'dart:ui' as ui;

import 'qr_visual_config.dart';

/// Draws decorative frames outside the QR quiet zone.
void paintQrFrame(
  ui.Canvas canvas,
  ui.Size size,
  QrFrameStyle frame,
  ui.Color color,
) {
  if (frame == QrFrameStyle.none) return;
  final side = size.shortestSide;
  final inset = side * .025;
  final strokeWidth = (side * .007).clamp(1.4, 6.0);
  final stroke = ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = strokeWidth;
  final fill = ui.Paint()..color = color;
  final softFill = ui.Paint()..color = color.withValues(alpha: .12);
  final bounds = ui.Rect.fromLTWH(
    inset,
    inset,
    side - inset * 2,
    side - inset * 2,
  );

  // A refined double outline provides a consistent visual system.
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(bounds, ui.Radius.circular(side * .055)),
    stroke,
  );
  if (frame != QrFrameStyle.simple) {
    final inner = bounds.deflate(side * .018);
    final fineStroke = ui.Paint()
      ..color = color.withValues(alpha: .62)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = (strokeWidth * .45).clamp(.8, 2.5);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(inner, ui.Radius.circular(side * .042)),
      fineStroke,
    );
  }

  final corners = <ui.Offset>[
    ui.Offset(side * .095, side * .095),
    ui.Offset(side * .905, side * .095),
    ui.Offset(side * .095, side * .905),
    ui.Offset(side * .905, side * .905),
  ];

  switch (frame) {
    case QrFrameStyle.none:
      break;
    case QrFrameStyle.simple:
      _drawCornerBrackets(canvas, side, stroke, .14, .14);
      _drawDiamond(canvas, ui.Offset(side / 2, side * .035), side * .012, fill);
      _drawDiamond(canvas, ui.Offset(side / 2, side * .965), side * .012, fill);
      break;
    case QrFrameStyle.floral:
      for (final p in corners) {
        _drawFlower(canvas, p, side * .035, fill, side);
      }
      _drawDotChain(canvas, side, fill, topAndBottom: true);
      break;
    case QrFrameStyle.botanical:
      for (var i = 0; i < 4; i++) {
        final x = side * (.25 + i * .167);
        _drawLeafSprig(
          canvas,
          ui.Offset(x, side * .045),
          side * .065,
          fill,
          -1,
        );
        _drawLeafSprig(canvas, ui.Offset(x, side * .955), side * .065, fill, 1);
      }
      for (final p in corners) {
        _drawLeafSprig(canvas, p, side * .07, fill, p.dx < side / 2 ? 1 : -1);
      }
      break;
    case QrFrameStyle.stars:
      for (final p in corners) {
        _drawStar(canvas, p, side * .038, fill);
        _drawStar(
          canvas,
          ui.Offset(
            p.dx + (p.dx < side / 2 ? side * .045 : -side * .045),
            p.dy + (p.dy < side / 2 ? side * .025 : -side * .025),
          ),
          side * .014,
          fill,
        );
      }
      _drawDotChain(canvas, side, fill, topAndBottom: true);
      break;
    case QrFrameStyle.hearts:
      for (final p in corners) {
        _drawHeart(canvas, p, side * .075, fill);
      }
      _drawDotChain(canvas, side, fill, topAndBottom: true, count: 9);
      break;
    case QrFrameStyle.confetti:
      final confettiColors = <ui.Color>[
        color,
        color.withValues(alpha: .65),
        color.withValues(alpha: .35),
      ];
      for (var i = 0; i < 18; i++) {
        final x = side * (.08 + (i % 9) * .105);
        final y = side * (i.isEven ? .055 : .945);
        final paint = ui.Paint()
          ..color = confettiColors[i % confettiColors.length];
        if (i % 3 == 0) {
          _drawStar(canvas, ui.Offset(x, y), side * .014, paint);
        } else if (i % 3 == 1) {
          canvas.drawCircle(ui.Offset(x, y), side * .009, paint);
        } else {
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(i * .37);
          canvas.drawRRect(
            ui.RRect.fromRectAndRadius(
              ui.Rect.fromCenter(
                center: ui.Offset.zero,
                width: side * .035,
                height: side * .012,
              ),
              ui.Radius.circular(side * .006),
            ),
            paint,
          );
          canvas.restore();
        }
      }
      break;
    case QrFrameStyle.text:
      // The lower badge reserves a dedicated, clean area for the CTA.
      final badge = ui.Rect.fromLTWH(
        side * .16,
        side * .82,
        side * .68,
        side * .105,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(badge, ui.Radius.circular(side * .035)),
        softFill,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(badge, ui.Radius.circular(side * .035)),
        stroke,
      );
      _drawCornerBrackets(canvas, side, stroke, .115, .115);
      _drawDiamond(
        canvas,
        ui.Offset(side * .12, side * .875),
        side * .012,
        fill,
      );
      _drawDiamond(
        canvas,
        ui.Offset(side * .88, side * .875),
        side * .012,
        fill,
      );
      break;
  }
}

void _drawCornerBrackets(
  ui.Canvas canvas,
  double side,
  ui.Paint paint,
  double xSize,
  double ySize,
) {
  for (final x in [.045, .955]) {
    for (final y in [.045, .955]) {
      final sx = x < .5 ? 1.0 : -1.0;
      final sy = y < .5 ? 1.0 : -1.0;
      final path = ui.Path()
        ..moveTo(side * x, side * (y + sy * ySize))
        ..lineTo(side * x, side * y)
        ..lineTo(side * (x + sx * xSize), side * y);
      canvas.drawPath(path, paint);
    }
  }
}

void _drawFlower(
  ui.Canvas canvas,
  ui.Offset center,
  double radius,
  ui.Paint paint,
  double side,
) {
  for (var i = 0; i < 8; i++) {
    final angle = i * math.pi / 4;
    final petalCenter = ui.Offset(
      center.dx + math.cos(angle) * radius * .58,
      center.dy + math.sin(angle) * radius * .58,
    );
    canvas.drawCircle(petalCenter, radius * .36, paint);
  }
  canvas.drawCircle(
    center,
    radius * .24,
    ui.Paint()..color = const ui.Color(0xFFFFC857),
  );
  canvas.drawCircle(
    center,
    radius * .58,
    ui.Paint()
      ..color = paint.color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = (side * .003).clamp(.8, 2.0),
  );
}

void _drawLeafSprig(
  ui.Canvas canvas,
  ui.Offset origin,
  double length,
  ui.Paint paint,
  double direction,
) {
  final stem = ui.Paint()
    ..color = paint.color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = (length * .055).clamp(.8, 2.0)
    ..strokeCap = ui.StrokeCap.round;
  canvas.drawLine(
    origin,
    ui.Offset(origin.dx + length * direction, origin.dy),
    stem,
  );
  for (var i = 0; i < 3; i++) {
    final x = origin.dx + length * direction * (.28 + i * .23);
    final y = origin.dy + (i.isEven ? -1 : 1) * length * .22;
    final leaf = ui.Rect.fromCenter(
      center: ui.Offset(x, y),
      width: length * .34,
      height: length * .18,
    );
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(direction * (i.isEven ? -.55 : .55));
    canvas.drawOval(leaf.shift(ui.Offset(-x, -y)), paint);
    canvas.restore();
  }
}

void _drawHeart(
  ui.Canvas canvas,
  ui.Offset center,
  double size,
  ui.Paint paint,
) {
  final path = ui.Path()
    ..moveTo(center.dx, center.dy + size * .42)
    ..cubicTo(
      center.dx - size * .12,
      center.dy + size * .24,
      center.dx - size * .62,
      center.dy - size * .08,
      center.dx - size * .42,
      center.dy - size * .42,
    )
    ..cubicTo(
      center.dx - size * .24,
      center.dy - size * .68,
      center.dx - size * .06,
      center.dy - size * .46,
      center.dx,
      center.dy - size * .28,
    )
    ..cubicTo(
      center.dx + size * .14,
      center.dy - size * .52,
      center.dx + size * .43,
      center.dy - size * .61,
      center.dx + size * .5,
      center.dy - size * .3,
    )
    ..cubicTo(
      center.dx + size * .61,
      center.dy - size * .02,
      center.dx + size * .15,
      center.dy + size * .31,
      center.dx,
      center.dy + size * .42,
    )
    ..close();
  canvas.drawPath(path, paint);
}

void _drawDotChain(
  ui.Canvas canvas,
  double side,
  ui.Paint paint, {
  required bool topAndBottom,
  int count = 13,
}) {
  for (var i = 0; i < count; i++) {
    final x = side * (.19 + i * (.62 / (count - 1)));
    canvas.drawCircle(ui.Offset(x, side * .045), side * .0055, paint);
    if (topAndBottom) {
      canvas.drawCircle(ui.Offset(x, side * .955), side * .0055, paint);
    }
  }
}

void _drawDiamond(
  ui.Canvas canvas,
  ui.Offset center,
  double radius,
  ui.Paint paint,
) {
  final path = ui.Path()
    ..moveTo(center.dx, center.dy - radius)
    ..lineTo(center.dx + radius, center.dy)
    ..lineTo(center.dx, center.dy + radius)
    ..lineTo(center.dx - radius, center.dy)
    ..close();
  canvas.drawPath(path, paint);
}

void _drawStar(
  ui.Canvas canvas,
  ui.Offset center,
  double radius,
  ui.Paint paint,
) {
  final path = ui.Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? radius : radius * .42;
    final angle = -math.pi / 2 + i * math.pi / 5;
    final point = ui.Offset(
      center.dx + math.cos(angle) * r,
      center.dy + math.sin(angle) * r,
    );
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  path.close();
  canvas.drawPath(path, paint);
}
