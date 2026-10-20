import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/data/app_database.dart';
import 'package:qr_ops/data/sqlite_qr_record_repository.dart';
import 'package:qr_ops/features/qr_create/qr_creation_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
            const QrContentDraft(type: QrContentType.url, value: 'exemplo.com'),
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
}
