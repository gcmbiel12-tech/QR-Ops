import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';
import 'package:qr_ops/domain/qr_ops_plan.dart';
import 'package:qr_ops/features/qr_create/qr_png_exporter.dart';
import 'package:qr_ops/features/qr_create/qr_visual_config.dart';
import 'package:zxing2/qrcode.dart';

void main() {
  test(
    'visual library has distinct models grouped in all requested categories',
    () {
      expect(QrVisualLibrary.models.length, 9);
      expect(
        QrVisualLibrary.models.map((model) => model.id).toSet().length,
        QrVisualLibrary.models.length,
      );
      for (final category in QrVisualCategory.values) {
        expect(
          QrVisualLibrary.models.any((model) => model.category == category),
          isTrue,
          reason: category.label,
        );
      }
      expect(QrVisualLibrary.palettes.length, greaterThanOrEqualTo(6));
    },
  );

  test('plan metadata separates basic and expanded visual capabilities', () {
    expect(QrOpsPlans.free.customVisualColors, isFalse);
    expect(QrOpsPlans.professional.customVisualColors, isTrue);
    expect(
      QrOpsPlans.free.visualModelIds.length,
      lessThan(QrOpsPlans.professional.visualModelIds.length),
    );
    expect(
      QrOpsPlans.free.visualPaletteIds.length,
      lessThan(QrOpsPlans.professional.visualPaletteIds.length),
    );
    expect(QrOpsPlans.professional.visualFrames, contains('floral'));
    expect(QrOpsPlans.free.visualFrames, isNot(contains('floral')));
  });

  test('all preset palettes meet the minimum contrast ratio', () {
    for (final palette in QrVisualLibrary.palettes) {
      expect(
        contrastRatio(palette.foreground, palette.background),
        greaterThanOrEqualTo(4.5),
        reason: palette.name,
      );
    }
    expect(
      contrastRatio(const ui.Color(0xFF777777), const ui.Color(0xFF888888)),
      lessThan(4.5),
    );
  });

  test(
    'exports square PNG at each supported resolution with each frame style',
    () async {
      const exporter = QrPngExporter();
      final matrix = QrImage(
        QrCode(
          payload: QrPayload.fromString('https://example.com'),
          errorCorrectLevel: QrErrorCorrectLevel.high,
        ),
      );

      for (final dimension in [256, 512, 1024, 2048]) {
        final png = await exporter.export(matrix, dimension: dimension);
        final codec = await ui.instantiateImageCodec(png);
        try {
          final image = (await codec.getNextFrame()).image;
          expect(image.width, dimension);
          expect(image.height, dimension);
          image.dispose();
        } finally {
          codec.dispose();
        }
      }

      for (final frame in QrFrameStyle.values) {
        final png = await exporter.export(
          matrix,
          dimension: 256,
          frame: frame,
          callToAction: frame.hasCallToAction ? 'Texto editado' : null,
          foreground: const ui.Color(0xFF12345A),
          background: const ui.Color(0xFFFFFFFF),
        );
        expect(png.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
        expect(
          await _decodePngText(png),
          'https://example.com',
          reason: frame.label,
        );
      }
    },
  );
}

Future<String> _decodePngText(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('Could not read PNG pixels.');
      final rgba = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final pixels = Int32List(image.width * image.height);
      for (var i = 0; i < pixels.length; i++) {
        final offset = i * 4;
        pixels[i] =
            (rgba[offset + 3] << 24) |
            (rgba[offset] << 16) |
            (rgba[offset + 1] << 8) |
            rgba[offset + 2];
      }
      final source = RGBLuminanceSource(image.width, image.height, pixels);
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      return QRCodeReader().decode(bitmap).text;
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
