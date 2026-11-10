import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/data/app_database.dart';
import 'package:qr_ops/data/sqlite_qr_record_repository.dart';
import 'package:qr_ops/data/sqlite_qr_sync_outbox.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/domain/qr_sync_contract.dart';
import 'package:qr_ops/domain/sync_owner_context.dart';
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
        QrRecord.created(
          content: 'texto de teste',
          name: 'Menu',
          description: 'Menu publico',
          createdAt: createdAt,
        ),
      );

      expect(inserted.id, isNotEmpty);
      expect(inserted.operation, QrRecordOperation.create);
      expect(inserted.symbology, 'qr');
      expect(inserted.contentType, 'text');
      expect(inserted.content, 'texto de teste');
      expect(inserted.name, 'Menu');
      expect(inserted.description, 'Menu publico');
      expect(inserted.createdAt, createdAt);
      final loaded = await repository.findById(inserted.id);
      expect(loaded?.id, inserted.id);
      expect(loaded?.content, inserted.content);
      expect(loaded?.name, 'Menu');
      expect(loaded?.description, 'Menu publico');
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
        final owner = SyncOwnerContext()..update('user-a');
        final fileRepository = SqliteQrRecordRepository(
          fileDatabase,
          syncOwnerContext: owner,
        );
        final inserted = await fileRepository.insert(
          QrRecord.created(content: 'persistir entre conexões'),
        );
        expect(
          await SqliteQrSyncOutbox(fileDatabase).pendingCount('user-a'),
          1,
        );

        final firstConnection = fileDatabase;
        await firstConnection.close();
        fileDatabase = null;
        fileDatabase = await AppDatabase(
          factory: databaseFactoryFfi,
          path: path,
        ).open();

        final restoredOwner = SyncOwnerContext()..update('user-a');
        final restored = await SqliteQrRecordRepository(
          fileDatabase,
          syncOwnerContext: restoredOwner,
        ).findById(inserted.id);
        expect(restored?.id, inserted.id);
        expect(restored?.content, 'persistir entre conexões');
        expect(
          await SqliteQrSyncOutbox(fileDatabase).pendingCount('user-a'),
          1,
        );
      } finally {
        await fileDatabase?.close();
      }
    },
  );

  test('updates saved metadata without changing QR content or ID', () async {
    final original = await repository.insert(
      QrRecord.created(content: 'https://example.org', name: 'Old name'),
    );
    final updated = QrRecord(
      id: original.id,
      operation: original.operation,
      symbology: original.symbology,
      contentType: original.contentType,
      content: original.content,
      name: 'New name',
      description: 'New description',
      createdAt: original.createdAt,
    );
    expect(await repository.updateById(updated), isTrue);
    final loaded = await repository.findById(original.id);
    expect(loaded?.content, 'https://example.org');
    expect(loaded?.name, 'New name');
    expect(loaded?.description, 'New description');
  });
  test(
    'retention removes only read records strictly older than seven days',
    () async {
      final now = DateTime.now().toUtc();
      final cutoff = now.subtract(const Duration(days: 7));
      final oldRead = await repository.insert(
        QrRecord.read(
          content: 'old read',
          symbology: 'qr',
          createdAt: cutoff.subtract(const Duration(seconds: 1)),
        ),
      );
      final oldCreated = await repository.insert(
        QrRecord.created(
          content: 'saved library item',
          createdAt: cutoff.subtract(const Duration(days: 2)),
        ),
      );
      final recentRead = await repository.insert(
        QrRecord.read(content: 'recent read', symbology: 'qr', createdAt: now),
      );
      expect(await repository.pruneReadHistoryBefore(cutoff), 1);
      expect(await repository.findById(oldRead.id), isNull);
      expect(
        (await repository.findById(oldCreated.id))?.content,
        'saved library item',
      );
      expect(
        (await repository.findById(recentRead.id))?.content,
        'recent read',
      );
      expect(await repository.pruneReadHistoryBefore(cutoff), 0);
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

  test(
    'persists owner-scoped sync operations atomically with local mutations',
    () async {
      final owner = SyncOwnerContext()..update('user-a');
      repository = SqliteQrRecordRepository(database, syncOwnerContext: owner);
      final outbox = SqliteQrSyncOutbox(database);
      final record = await repository.insert(
        QrRecord.created(content: 'queued create'),
      );
      final updated = QrRecord(
        id: record.id,
        operation: record.operation,
        symbology: record.symbology,
        contentType: record.contentType,
        content: record.content,
        name: 'updated metadata',
        createdAt: record.createdAt,
        revision: record.revision,
      );
      await repository.updateById(updated);
      await repository.deleteById(record.id);

      final pending = await outbox.pendingForOwner('user-a', limit: 100);
      expect(pending, hasLength(3));
      expect(pending.map((item) => item.type), [
        QrSyncMutationType.upsert,
        QrSyncMutationType.upsert,
        QrSyncMutationType.delete,
      ]);
      expect(pending.map((item) => item.baseRevision), [null, 1, 2]);
      expect(await outbox.pendingForOwner('user-b'), isEmpty);

      final reopenedOutbox = SqliteQrSyncOutbox(database);
      expect(await reopenedOutbox.pendingForOwner('user-a'), hasLength(3));
      expect(await reopenedOutbox.pendingCount('user-a'), 3);
    },
  );

  test('isolates local records by account and only claims legacy data after consent', () async {
    final legacy = await repository.insert(
      QrRecord.created(content: 'legacy local record'),
    );
    final unselectedLegacy = await repository.insert(
      QrRecord.created(content: 'legacy record not selected'),
    );
    final ownerA = SyncOwnerContext()..update('user-a');
    final accountA = SqliteQrRecordRepository(
      database,
      syncOwnerContext: ownerA,
    );

    expect(await accountA.listLatest(), isEmpty);
    expect(
      (await accountA.listUnownedRecords(ownerId: 'user-a'))
          .map((item) => item.id),
      containsAll([legacy.id, unselectedLegacy.id]),
    );
    expect(
      await accountA.claimUnownedRecords('user-a', recordIds: {legacy.id}),
      1,
    );
    expect((await accountA.listLatest()).map((item) => item.id), [legacy.id]);
    expect(
      (await accountA.listUnownedRecords(ownerId: 'user-a'))
          .map((item) => item.id),
      [unselectedLegacy.id],
    );

    final recordA = await accountA.insert(
      QrRecord.created(content: 'private A'),
    );
    final ownerB = SyncOwnerContext()..update('user-b');
    final accountB = SqliteQrRecordRepository(
      database,
      syncOwnerContext: ownerB,
    );
    expect(await accountB.listLatest(), isEmpty);
    expect(await accountB.findById(recordA.id), isNull);
    expect(await accountB.deleteById(recordA.id), isFalse);

    final recordB = await accountB.insert(
      QrRecord.created(content: 'private B'),
    );
    expect(
      (await accountA.listLatest()).map((item) => item.content),
      contains('private A'),
    );
    expect(
      (await accountA.listLatest()).map((item) => item.content),
      isNot(contains('private B')),
    );
    expect((await accountB.listLatest()).map((item) => item.content), [
      'private B',
    ]);
    expect(await accountA.findById(recordB.id), isNull);
  });

  test('adopts a matching legacy record when it is confirmed by the account remote snapshot', () async {
    final legacy = await repository.insert(
      QrRecord.created(content: 'previously synced record', name: 'Legacy'),
    );
    final owner = SyncOwnerContext()..update('user-a');
    final account = SqliteQrRecordRepository(database, syncOwnerContext: owner);
    final remote = legacy.withRevision(3);

    await account.applyRemoteRecord(remote, ownerId: 'user-a');

    expect(await repository.findById(legacy.id), isNull);
    expect((await account.findById(legacy.id))?.revision, 3);
    expect((await account.findById(legacy.id))?.content, legacy.content);
  });

  test('does not let another account claim legacy rows queued for the first account', () async {
    final ownerA = SyncOwnerContext()..update('user-a');
    final accountA = SqliteQrRecordRepository(
      database,
      syncOwnerContext: ownerA,
    );
    final record = await accountA.insert(
      QrRecord.created(content: 'queued for A'),
    );
    await database.update(
      'qr_records',
      {'owner_id': null},
      where: 'id = ?',
      whereArgs: [record.id],
    );

    final ownerB = SyncOwnerContext()..update('user-b');
    final accountB = SqliteQrRecordRepository(
      database,
      syncOwnerContext: ownerB,
    );
    expect(await accountB.listUnownedRecords(ownerId: 'user-b'), isEmpty);
    expect(
      await accountB.claimUnownedRecords('user-b', recordIds: {record.id}),
      0,
    );
    expect(
      (await accountA.listUnownedRecords(ownerId: 'user-a')).single.id,
      record.id,
    );
    expect(
      await accountA.claimUnownedRecords('user-a', recordIds: {record.id}),
      1,
    );
    expect((await accountA.listLatest()).single.id, record.id);
  });

  test(
    'does not queue local operations without an authenticated owner',
    () async {
      final record = await repository.insert(
        QrRecord.created(content: 'local only'),
      );
      expect(await repository.findById(record.id), isNotNull);
      expect(await SqliteQrSyncOutbox(database).pendingCount('user-a'), 0);
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
