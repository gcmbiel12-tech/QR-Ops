import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb.dart';
import 'package:idb_shim/idb_browser.dart' show idbFactoryBrowser;
import 'package:qr_ops/data/indexed_db_qr_record_repository.dart';
import 'package:qr_ops/data/indexed_db_qr_sync_outbox.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/domain/qr_sync_contract.dart';
import 'package:qr_ops/domain/sync_owner_context.dart';

void main() {
  late IndexedDbQrRecordRepository repository;
  late String databaseName;

  setUp(() {
    databaseName = 'qr_ops_test_${DateTime.now().microsecondsSinceEpoch}';
    repository = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
    );
  });

  tearDown(() => repository.deleteDatabase());

  test('inserts and reads the original record fields', () async {
    final record = QrRecord.created(
      content: '  conteúdo original  ',
      createdAt: DateTime.utc(2026, 10, 16, 12, 30),
    );

    final inserted = await repository.insert(record);
    final loaded = await repository.findById(record.id);

    expect(inserted.id, record.id);
    expect(loaded?.id, record.id);
    expect(loaded?.content, '  conteúdo original  ');
    expect(loaded?.createdAt, record.createdAt);
    expect(loaded?.operation, QrRecordOperation.create);
    expect(loaded?.symbology, 'qr');
    expect(loaded?.contentType, 'text');
  });

  test('lists latest records first and applies the requested limit', () async {
    await repository.insert(
      QrRecord.created(
        content: 'mais antigo',
        createdAt: DateTime.utc(2026, 10, 15),
      ),
    );
    await repository.insert(
      QrRecord.created(
        content: 'mais recente',
        createdAt: DateTime.utc(2026, 10, 16),
      ),
    );

    expect(
      (await repository.listLatest(limit: 1)).single.content,
      'mais recente',
    );
    expect(await repository.listLatest(), hasLength(2));
    await expectLater(repository.listLatest(limit: 0), throwsArgumentError);
  });

  test('persists across repository and database re-opening', () async {
    final record = await repository.insert(
      QrRecord.created(content: 'permanece após recarregar'),
    );
    await repository.close();
    repository = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
    );

    final restored = await repository.findById(record.id);
    expect(restored?.id, record.id);
    expect(restored?.content, 'permanece após recarregar');
  });

  test(
    'updates saved metadata while preserving the original content and identity',
    () async {
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
    },
  );
  test(
    'retention deletes old reads but preserves library items and recent reads',
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
          content: 'saved item',
          createdAt: cutoff.subtract(const Duration(days: 1)),
        ),
      );
      final recentRead = await repository.insert(
        QrRecord.read(content: 'recent read', symbology: 'qr', createdAt: now),
      );
      expect(await repository.pruneReadHistoryBefore(cutoff), 1);
      expect(await repository.findById(oldRead.id), isNull);
      expect((await repository.findById(oldCreated.id))?.content, 'saved item');
      expect(
        (await repository.findById(recentRead.id))?.content,
        'recent read',
      );
      expect(await repository.pruneReadHistoryBefore(cutoff), 0);
    },
  );
  test('deletes an existing record and reports missing records', () async {
    final record = await repository.insert(
      QrRecord.created(content: 'remover'),
    );

    expect(await repository.deleteById(record.id), isTrue);
    expect(await repository.findById(record.id), isNull);
    expect(await repository.deleteById(record.id), isFalse);
  });

  test('rejects invalid input and duplicate identifiers', () async {
    await expectLater(
      repository.insert(QrRecord.created(content: '  ')),
      throwsArgumentError,
    );
    final record = await repository.insert(
      QrRecord.created(content: 'conteúdo'),
    );
    await expectLater(repository.insert(record), throwsA(anything));
  });

  test('persists ordered owner-scoped sync mutations in IndexedDB', () async {
    final owner = SyncOwnerContext()..update('user-a');
    repository = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
      syncOwnerContext: owner,
    );
    final outbox = IndexedDbQrSyncOutbox(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
    );
    final record = await repository.insert(
      QrRecord.created(content: 'queued create'),
    );
    final updated = QrRecord(
      id: record.id,
      operation: record.operation,
      symbology: record.symbology,
      contentType: record.contentType,
      content: record.content,
      name: 'metadata updated',
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

    await repository.close();
    repository = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
    );
    final reopenedOutbox = IndexedDbQrSyncOutbox(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
    );
    expect(await reopenedOutbox.pendingForOwner('user-a'), hasLength(3));
    await reopenedOutbox.close();
  });

  test('isolates account records and preserves unowned legacy records until claimed', () async {
    final legacy = await repository.insert(
      QrRecord.created(content: 'legacy local record'),
    );
    final unselectedLegacy = await repository.insert(
      QrRecord.created(content: 'legacy record not selected'),
    );
    final ownerA = SyncOwnerContext()..update('user-a');
    final accountA = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
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
    final accountB = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
      syncOwnerContext: ownerB,
    );
    expect(await accountB.listLatest(), isEmpty);
    expect(await accountB.findById(recordA.id), isNull);
    expect(await accountB.deleteById(recordA.id), isFalse);
    await accountB.insert(QrRecord.created(content: 'private B'));
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
    await accountA.close();
    await accountB.close();
  });

  test('adopts a matching legacy record when confirmed by the account remote snapshot', () async {
    final legacy = await repository.insert(
      QrRecord.created(content: 'previously synced record', name: 'Legacy'),
    );
    final owner = SyncOwnerContext()..update('user-a');
    final account = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
      syncOwnerContext: owner,
    );
    final remote = legacy.withRevision(3);

    await account.applyRemoteRecord(remote, ownerId: 'user-a');

    expect(await repository.findById(legacy.id), isNull);
    expect((await account.findById(legacy.id))?.revision, 3);
    expect((await account.findById(legacy.id))?.content, legacy.content);
    await account.close();
  });

  test('does not let another account claim a legacy row queued for the first account', () async {
    final ownerA = SyncOwnerContext()..update('user-a');
    final accountA = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
      syncOwnerContext: ownerA,
    );
    final record = await accountA.insert(
      QrRecord.created(content: 'queued for A'),
    );
    await accountA.close();
    final raw = await idbFactoryBrowser.open(databaseName);
    final transaction = raw.transaction('qr_records', idbModeReadWrite);
    final store = transaction.objectStore('qr_records');
    final row = Map<Object?, Object?>.from(
      (await store.getObject(record.id)) as Map,
    )..['owner_id'] = null;
    await store.put(row);
    await transaction.completed;
    raw.close();

    final ownerB = SyncOwnerContext()..update('user-b');
    final accountB = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
      syncOwnerContext: ownerB,
    );
    expect(await accountB.listUnownedRecords(ownerId: 'user-b'), isEmpty);
    expect(
      await accountB.claimUnownedRecords('user-b', recordIds: {record.id}),
      0,
    );
    await accountB.close();

    final restoredA = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
      syncOwnerContext: ownerA,
    );
    expect(
      (await restoredA.listUnownedRecords(ownerId: 'user-a')).single.id,
      record.id,
    );
    expect(
      await restoredA.claimUnownedRecords('user-a', recordIds: {record.id}),
      1,
    );
    expect((await restoredA.listLatest()).single.id, record.id);
    await restoredA.close();
  });

  test('propagates IndexedDB open failures to the caller', () async {
    final failingRepository = IndexedDbQrRecordRepository(
      factory: _FailingIdbFactory(),
      databaseName: databaseName,
    );

    await expectLater(failingRepository.listLatest(), throwsStateError);
  });

  test(
    'observes failed read transactions and propagates the read error',
    () async {
      final failingRepository = IndexedDbQrRecordRepository(
        factory: _FailingReadIdbFactory(),
        databaseName: databaseName,
      );

      await expectLater(failingRepository.listLatest(), throwsStateError);
      await expectLater(
        failingRepository.findById('missing'),
        throwsStateError,
      );
    },
  );
}

class _FailingIdbFactory extends Fake implements IdbFactory {
  @override
  Future<Database> open(
    String dbName, {
    int? version,
    OnUpgradeNeededFunction? onUpgradeNeeded,
    OnBlockedFunction? onBlocked,
  }) => Future.error(StateError('IndexedDB indisponível'));
}

class _FailingReadIdbFactory extends Fake implements IdbFactory {
  @override
  Future<Database> open(
    String dbName, {
    int? version,
    OnUpgradeNeededFunction? onUpgradeNeeded,
    OnBlockedFunction? onBlocked,
  }) => Future.value(_FailingReadDatabase());
}

class _FailingReadDatabase extends Fake implements Database {
  @override
  Transaction transaction(Object storeNameOrStoreNames, String mode) =>
      _FailingReadTransaction(this);

  @override
  void close() {}
}

class _FailingReadTransaction extends Fake implements Transaction {
  _FailingReadTransaction(this.database);

  @override
  final Database database;

  @override
  ObjectStore objectStore(String name) => _FailingReadObjectStore();

  @override
  Future<Database> get completed =>
      Future.error(StateError('IndexedDB read transaction failed'));

  @override
  Iterable<String> get objectStoreNames => const [_storeNameForTest];

  @override
  void abort() {}
}

class _FailingReadObjectStore extends Fake implements ObjectStore {
  @override
  Future<List<Object>> getAll([Object? query, int? count]) =>
      Future.error(StateError('IndexedDB read failed'));

  @override
  Future<Object?> getObject(Object key) =>
      Future.error(StateError('IndexedDB read failed'));
}

const _storeNameForTest = 'qr_records';
