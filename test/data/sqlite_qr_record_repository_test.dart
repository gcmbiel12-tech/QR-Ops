import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/data/app_database.dart';
import 'package:qr_ops/data/sqlite_qr_record_repository.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late SqliteQrRecordRepository repository;
  late Database database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    ).open();
    repository = SqliteQrRecordRepository(database);
  });

  tearDown(() => database.close());

  test(
    'inserts and reads a QR history record without changing its content',
    () async {
      final createdAt = DateTime.utc(2026, 10, 16, 12, 30);
      final inserted = await repository.insert(
        QrRecord.created(content: 'texto de teste', createdAt: createdAt),
      );

      expect(inserted.id, isNotEmpty);
      expect(inserted.operation, QrRecordOperation.create);
      expect(inserted.symbology, 'qr');
      expect(inserted.contentType, 'text');
      expect(inserted.content, 'texto de teste');
      expect(inserted.createdAt, createdAt);
      final loaded = await repository.findById(inserted.id);
      expect(loaded?.id, inserted.id);
      expect(loaded?.content, inserted.content);
      expect(loaded?.createdAt, inserted.createdAt);
    },
  );

  test('lists newest records first and applies the requested limit', () async {
    await repository.insert(
      QrRecord.created(
        content: 'primeiro',
        createdAt: DateTime.utc(2026, 10, 15),
      ),
    );
    await repository.insert(
      QrRecord.created(
        content: 'segundo',
        createdAt: DateTime.utc(2026, 10, 16),
      ),
    );

    final records = await repository.listLatest(limit: 1);
    expect(records, hasLength(1));
    expect(records.single.content, 'segundo');
    expect(await repository.listLatest(), hasLength(2));
  });

  test(
    'retains records after closing and reopening a file-backed database',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'qr_ops_reopen_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}qr_ops.db';

      Database? fileDatabase;
      try {
        fileDatabase = await AppDatabase(
          factory: databaseFactoryFfi,
          path: path,
        ).open();
        final inserted = await SqliteQrRecordRepository(fileDatabase)
            .insert(QrRecord.created(content: 'persistir entre conexões'));

        final firstConnection = fileDatabase;
        await firstConnection.close();
        fileDatabase = null;
        fileDatabase = await AppDatabase(
          factory: databaseFactoryFfi,
          path: path,
        ).open();

        final restored = await SqliteQrRecordRepository(fileDatabase)
            .findById(inserted.id);
        expect(restored?.id, inserted.id);
        expect(restored?.content, 'persistir entre conexões');
      } finally {
        await fileDatabase?.close();
      }
    },
  );

  test(
    'deletes only the selected record and returns whether it existed',
    () async {
      final inserted = await repository.insert(
        QrRecord.created(content: 'remover'),
      );

      expect(await repository.deleteById(inserted.id), isTrue);
      expect(await repository.findById(inserted.id), isNull);
      expect(await repository.deleteById(inserted.id), isFalse);
    },
  );

  test('rejects invalid repository operations', () async {
    final persisted = await repository.insert(
      QrRecord.created(content: 'já persistido'),
    );
    await expectLater(
      repository.insert(persisted),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      repository.insert(QrRecord.created(content: '  ')),
      throwsArgumentError,
    );
    await expectLater(repository.listLatest(limit: 0), throwsArgumentError);
  });
}
