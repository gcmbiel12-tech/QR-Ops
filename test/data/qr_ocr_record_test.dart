import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/data/app_database.dart';
import 'package:qr_ops/data/sqlite_qr_record_repository.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/domain/sync_owner_context.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late SyncOwnerContext owner;
  late SqliteQrRecordRepository repository;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = await AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    ).open();
    owner = SyncOwnerContext()..update('user-local-test');
    repository = SqliteQrRecordRepository(database, syncOwnerContext: owner);
  });
  tearDown(() => database.close());

  test(
    'stores editable OCR text locally and never enqueues it for remote sync',
    () async {
      final record = QrRecord.ocr(
        content: 'Texto reconhecido',
        name: 'Documento A',
      );
      await repository.insert(record);

      final loaded = await repository.findById(record.id);
      expect(loaded?.operation, QrRecordOperation.ocr);
      expect(loaded?.contentType, 'ocr_text');
      expect(loaded?.content, 'Texto reconhecido');
      expect(await database.query('qr_sync_outbox'), isEmpty);

      final updated = QrRecord(
        id: record.id,
        operation: QrRecordOperation.ocr,
        symbology: 'text',
        contentType: 'ocr_text',
        content: 'Texto corrigido',
        name: 'Documento revisado',
        createdAt: record.createdAt,
      );
      expect(await repository.updateById(updated), isTrue);
      expect(
        (await repository.findById(record.id))?.content,
        'Texto corrigido',
      );
      expect(await database.query('qr_sync_outbox'), isEmpty);

      expect(await repository.deleteById(record.id), isTrue);
      expect(await database.query('qr_sync_outbox'), isEmpty);
    },
  );
}
