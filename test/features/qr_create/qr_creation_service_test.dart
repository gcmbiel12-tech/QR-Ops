import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart' as qr;
import 'package:qr_ops/data/app_database.dart';
import 'package:qr_ops/data/sqlite_qr_record_repository.dart';
import 'package:qr_ops/features/qr_create/qr_creation_service.dart';
import 'package:qr_ops/features/qr_create/qr_png_exporter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zxing2/qrcode.dart';

void main() {
  late SqliteQrRecordRepository repository;
  late QrCreationService service;
  late Database database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    ).open();
    repository = SqliteQrRecordRepository(database);
    service = QrCreationService(repository);
  });

  tearDown(() => database.close());

  test('encodes and saves non-empty content locally', () async {
    final image = service.encode('https://example.com');
    final record = await service.create('https://example.com');

    expect(image.moduleCount, greaterThan(0));
    expect(record.content, 'https://example.com');
    expect(record.id, isNotEmpty);
    expect(await repository.listLatest(), hasLength(1));
  });

  test('rejects blank input without saving', () async {
    expect(
      () => service.encode('  \n '),
      throwsA(
        isA<QrContentException>().having(
          (error) => error.problem,
          'problem',
          QrContentProblem.empty,
        ),
      ),
    );
    await expectLater(service.create('  '), throwsA(isA<QrContentException>()));
    expect(await repository.listLatest(), isEmpty);
  });

  test('rejects payloads beyond QR capacity without saving', () async {
    final longContent = 'x' * 10000;

    expect(
      () => service.encode(longContent),
      throwsA(
        isA<QrContentException>().having(
          (error) => error.problem,
          'problem',
          QrContentProblem.tooLong,
        ),
      ),
    );
    expect(await repository.listLatest(), isEmpty);
  });

  test('composes standardized payloads for supported content types', () {
    expect(
      service
          .compose(
            const QrContentDraft(
              type: QrContentType.text,
              value: 'Olá, QR Ops',
            ),
          )
          .value,
      'Olá, QR Ops',
    );
    expect(
      service
          .compose(
            const QrContentDraft(
              type: QrContentType.url,
              value: 'https://exemplo.com',
            ),
          )
          .value,
      'https://exemplo.com',
    );
    expect(
      service
          .compose(
            const QrContentDraft(
              type: QrContentType.phone,
              value: '+55 (11) 99999-0000',
            ),
          )
          .value,
      'tel:+5511999990000',
    );
    expect(
      service
          .compose(
            const QrContentDraft(
              type: QrContentType.email,
              value: 'ops@exemplo.com',
              secondary: 'Ação & controle',
              tertiary: 'Olá equipe',
            ),
          )
          .value,
      'mailto:ops@exemplo.com?subject=A%C3%A7%C3%A3o%20%26%20controle&body=Ol%C3%A1%20equipe',
    );
    expect(
      service
          .compose(
            const QrContentDraft(
              type: QrContentType.sms,
              value: '+5511999990000',
              secondary: 'Cheguei',
            ),
          )
          .value,
      'sms:+5511999990000?body=Cheguei',
    );
    expect(
      service
          .compose(
            const QrContentDraft(
              type: QrContentType.whatsapp,
              value: '+55 (11) 99999-0000',
              secondary: 'Olá! Quero saber mais sobre vocês.',
            ),
          )
          .value,
      'https://wa.me/5511999990000?text=Ol%C3%A1!%20Quero%20saber%20mais%20sobre%20voc%C3%AAs.',
    );
    expect(
      service
          .compose(
            const QrContentDraft(
              type: QrContentType.wifi,
              value: 'Rede; operação',
              secondary: r'senha:123',
            ),
          )
          .value,
      r'WIFI:T:WPA;S:Rede\; operação;P:senha\:123;;',
    );
  });

  test(
    'rejects invalid structured values and keeps invalid data unsaved',
    () async {
      for (final draft in [
        const QrContentDraft(
          type: QrContentType.url,
          value: 'javascript:alert(1)',
        ),
        const QrContentDraft(type: QrContentType.url, value: 'exemplo.com'),
        const QrContentDraft(
          type: QrContentType.url,
          value: 'htp://example.com',
        ),
        const QrContentDraft(
          type: QrContentType.url,
          value: 'https://example.com/%zz',
        ),
        const QrContentDraft(type: QrContentType.url, value: ''),
        const QrContentDraft(
          type: QrContentType.url,
          value: 'https://exa mple.com',
        ),
        const QrContentDraft(
          type: QrContentType.url,
          value: 'https:///caminho',
        ),
        const QrContentDraft(type: QrContentType.phone, value: 'abc'),
        const QrContentDraft(type: QrContentType.email, value: 'invalido'),
        const QrContentDraft(type: QrContentType.wifi, value: 'Rede'),
      ]) {
        expect(
          () => service.compose(draft),
          throwsA(isA<QrContentException>()),
        );
      }
      expect(await repository.listLatest(), isEmpty);
    },
  );

  test('preserves complete HTTP and HTTPS URLs exactly', () {
    for (final url in [
      'https://Exemplo.com/caminho?q=ação%20e%20café&x=1#seção',
      'http://example.com/path?x=a%2Fb&y=2#fragment',
    ]) {
      expect(
        service
            .compose(QrContentDraft(type: QrContentType.url, value: url))
            .value,
        url,
      );
    }
  });

  test('rejects URL spaces instead of silently encoding or trimming them', () {
    for (final url in [
      'https://example.com/a b',
      ' https://example.com',
      'https://example.com ',
    ]) {
      expect(
        () => service.compose(
          QrContentDraft(type: QrContentType.url, value: url),
        ),
        throwsA(isA<QrContentException>()),
      );
    }
    const escapedUrl = 'https://example.com/a%20b';
    expect(
      service
          .compose(
            const QrContentDraft(type: QrContentType.url, value: escapedUrl),
          )
          .value,
      escapedUrl,
    );
  });

  test('validates empty and malformed input for every content type', () {
    final invalidDrafts = [
      const QrContentDraft(type: QrContentType.text),
      const QrContentDraft(type: QrContentType.url, value: 'example.com'),
      const QrContentDraft(type: QrContentType.phone, value: ''),
      const QrContentDraft(type: QrContentType.phone, value: 'abc'),
      const QrContentDraft(type: QrContentType.email, value: ''),
      const QrContentDraft(type: QrContentType.email, value: 'invalido'),
      const QrContentDraft(type: QrContentType.sms, value: ''),
      const QrContentDraft(type: QrContentType.sms, value: '+55abc'),
      const QrContentDraft(type: QrContentType.wifi, value: ''),
      const QrContentDraft(type: QrContentType.wifi, value: 'Rede'),
    ];

    for (final draft in invalidDrafts) {
      expect(
        () => service.compose(draft),
        throwsA(isA<QrContentException>()),
        reason: draft.type.name,
      );
    }
  });

  test('supports Wi-Fi security variants and escapes structured fields', () {
    expect(
      service
          .compose(
            const QrContentDraft(
              type: QrContentType.wifi,
              value: r'Rede\;: operação',
              secondary: r'senha\;,:',
              wifiSecurity: 'WEP',
            ),
          )
          .value,
      r'WIFI:T:WEP;S:Rede\\\;\: operação;P:senha\\\;\,\:;;',
    );
    expect(
      service
          .compose(
            const QrContentDraft(
              type: QrContentType.wifi,
              value: 'Rede aberta',
              wifiSecurity: 'nopass',
            ),
          )
          .value,
      'WIFI:T:nopass;S:Rede aberta;;',
    );
  });

  test('decodes ASCII and distinguishes Unicode bytes from ZXing text', () {
    const contents = ['Texto QR simples', 'ação, café, ç', '漢字', 'Teste 🚀'];

    final ascii = _decodeMatrix(service.encode(contents.first));
    expect(ascii.text, contents.first);
    expect(ascii.byteSegments, hasLength(1));
    expect(ascii.byteSegments.single, utf8.encode(contents.first));

    for (final content in contents.skip(1)) {
      final decoded = _decodeMatrix(service.encode(content));
      expect(decoded.byteSegments, hasLength(1), reason: content);
      expect(
        decoded.byteSegments.single,
        utf8.encode(content),
        reason: 'Bytes recuperados da matriz para $content',
      );
      // zxing2 0.2.4 decodes ECI UTF-8 bytes stored in Int8List as signed
      // values, so its text interpretation is not currently trustworthy.
      // Keep this distinct from the byte-level assertion above.
      expect(
        decoded.text,
        isNot(content),
        reason: 'Limitação documentada da interpretação textual do zxing2',
      );
    }
  });

  test('generates QR matrices for all supported content types', () {
    final drafts = [
      const QrContentDraft(type: QrContentType.text, value: 'Operação ção'),
      const QrContentDraft(
        type: QrContentType.url,
        value: 'https://exemplo.com',
      ),
      const QrContentDraft(type: QrContentType.phone, value: '+5511999990000'),
      const QrContentDraft(type: QrContentType.email, value: 'ops@exemplo.com'),
      const QrContentDraft(type: QrContentType.sms, value: '+5511999990000'),
      const QrContentDraft(
        type: QrContentType.wifi,
        value: 'Rede operacional',
        secondary: 'senha123',
      ),
    ];

    for (final draft in drafts) {
      final content = service.compose(draft);
      expect(service.encode(content.value).moduleCount, greaterThan(0));
    }
  });

  test(
    'stores the content type without changing the encoded payload',
    () async {
      final encoded = service.compose(
        const QrContentDraft(
          type: QrContentType.url,
          value: 'https://example.com',
        ),
      );
      final record = await service.create(
        encoded.value,
        contentType: encoded.type.storageValue,
      );
      expect(record.content, 'https://example.com');
      expect(record.contentType, 'url');
    },
  );

  test(
    'exports valid PNGs and decodes their final pixels independently',
    () async {
      const exporter = QrPngExporter();
      const payloads = [
        'Texto QR simples',
        'https://example.com/qr?setor=ops',
        'ação, café, ç',
        '漢字',
        'Teste 🚀',
      ];
      const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

      for (final payload in payloads) {
        final matrix = service.encode(payload);
        final png = await exporter.export(matrix);
        expect(png.take(8).toList(), pngSignature, reason: payload);

        final decoded = await _decodePng(png);
        final expectedDimension =
            (matrix.moduleCount + QrPngExporter.quietZoneModules * 2) *
            QrPngExporter.pixelsPerModule;
        expect(decoded.width, expectedDimension, reason: payload);
        expect(decoded.height, expectedDimension, reason: payload);
        expect(
          _hasWhiteQuietZone((
            width: decoded.width,
            height: decoded.height,
            rgba: decoded.rgba,
          )),
          isTrue,
          reason: payload,
        );

        for (var row = 0; row < matrix.moduleCount; row++) {
          for (var column = 0; column < matrix.moduleCount; column++) {
            final x =
                (column + QrPngExporter.quietZoneModules) *
                    QrPngExporter.pixelsPerModule +
                QrPngExporter.pixelsPerModule ~/ 2;
            final y =
                (row + QrPngExporter.quietZoneModules) *
                    QrPngExporter.pixelsPerModule +
                QrPngExporter.pixelsPerModule ~/ 2;
            expect(
              _isBlackPixel(decoded.rgba, decoded.width, x, y),
              matrix.isDark(row, column),
              reason: 'Matriz exportada: $payload, módulo $row,$column',
            );
          }
        }

        if (payload == 'Texto QR simples' ||
            payload == 'https://example.com/qr?setor=ops') {
          expect(decoded.text, payload, reason: payload);
        } else {
          expect(decoded.byteSegments, hasLength(1), reason: payload);
          expect(
            decoded.byteSegments.single,
            utf8.encode(payload),
            reason: 'Bytes recuperados do PNG para $payload',
          );
          expect(
            decoded.text,
            isNot(payload),
            reason: 'Limitação de interpretação Unicode do zxing2',
          );
        }
      }
    },
  );
}

({String text, List<List<int>> byteSegments}) _decodeMatrix(
  qr.QrImage qrImage,
) {
  const scale = 4;
  const quietZone = 4;
  final dimension = (qrImage.moduleCount + quietZone * 2) * scale;
  final pixels = Int32List(dimension * dimension);

  for (var y = 0; y < dimension; y++) {
    for (var x = 0; x < dimension; x++) {
      final moduleX = x ~/ scale - quietZone;
      final moduleY = y ~/ scale - quietZone;
      final isDark =
          moduleX >= 0 &&
          moduleX < qrImage.moduleCount &&
          moduleY >= 0 &&
          moduleY < qrImage.moduleCount &&
          qrImage.isDark(moduleY, moduleX);
      pixels[y * dimension + x] = isDark ? 0x000000 : 0xFFFFFF;
    }
  }

  final source = RGBLuminanceSource(dimension, dimension, pixels);
  final bitmap = BinaryBitmap(HybridBinarizer(source));
  final hints = DecodeHints()..put(DecodeHintType.pureBarcode);
  final result = QRCodeReader().decode(bitmap, hints: hints);
  final segments =
      result.resultMetadata[ResultMetadataType.byteSegments] as List<Int8List>?;
  return (
    text: result.text,
    byteSegments: [
      for (final segment in segments ?? <Int8List>[])
        segment.map((byte) => byte & 0xff).toList(growable: false),
    ],
  );
}

Future<
  ({
    int width,
    int height,
    Uint8List rgba,
    String text,
    List<List<int>> byteSegments,
  })
>
_decodePng(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final rgbaData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rgbaData == null) {
        throw StateError('Não foi possível decodificar o PNG exportado.');
      }
      final rgba = Uint8List.fromList(
        rgbaData.buffer.asUint8List(
          rgbaData.offsetInBytes,
          rgbaData.lengthInBytes,
        ),
      );
      final argb = Int32List(image.width * image.height);
      for (var pixel = 0; pixel < argb.length; pixel++) {
        final offset = pixel * 4;
        argb[pixel] =
            (rgba[offset + 3] << 24) |
            (rgba[offset] << 16) |
            (rgba[offset + 1] << 8) |
            rgba[offset + 2];
      }

      final source = RGBLuminanceSource(image.width, image.height, argb);
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      final hints = DecodeHints()..put(DecodeHintType.pureBarcode);
      final result = QRCodeReader().decode(bitmap, hints: hints);
      final segments =
          result.resultMetadata[ResultMetadataType.byteSegments]
              as List<Int8List>?;
      return (
        width: image.width,
        height: image.height,
        rgba: rgba,
        text: result.text,
        byteSegments: [
          for (final segment in segments ?? <Int8List>[])
            segment.map((byte) => byte & 0xff).toList(growable: false),
        ],
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

bool _hasWhiteQuietZone(({int width, int height, Uint8List rgba}) image) {
  final margin = QrPngExporter.quietZoneModules * QrPngExporter.pixelsPerModule;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (x >= margin &&
          x < image.width - margin &&
          y >= margin &&
          y < image.height - margin) {
        continue;
      }
      final offset = (y * image.width + x) * 4;
      if (image.rgba[offset] != 255 ||
          image.rgba[offset + 1] != 255 ||
          image.rgba[offset + 2] != 255 ||
          image.rgba[offset + 3] != 255) {
        return false;
      }
    }
  }
  return true;
}

bool _isBlackPixel(Uint8List rgba, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return rgba[offset] == 0 &&
      rgba[offset + 1] == 0 &&
      rgba[offset + 2] == 0 &&
      rgba[offset + 3] == 255;
}
