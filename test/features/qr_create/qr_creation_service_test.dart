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
}
