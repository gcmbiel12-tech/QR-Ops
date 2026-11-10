import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/data/app_database.dart';
import 'package:qr_ops/data/qr_sync_service.dart';
import 'package:qr_ops/data/sqlite_qr_record_repository.dart';
import 'package:qr_ops/data/sqlite_qr_sync_outbox.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/domain/qr_sync_contract.dart';
import 'package:qr_ops/domain/sync_owner_context.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late SyncOwnerContext owner;
  late SqliteQrRecordRepository repository;
  late SqliteQrSyncOutbox outbox;
  late _FakePullTransport transport;
  late QrSyncService service;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = await AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    ).open();
    owner = SyncOwnerContext()..update('user-a');
    repository = SqliteQrRecordRepository(database, syncOwnerContext: owner);
    outbox = SqliteQrSyncOutbox(database);
    transport = _FakePullTransport();
    service = QrSyncService(
      localRepository: repository,
      outbox: outbox,
      transport: transport,
      ownerContext: owner,
    );
  });

  tearDown(() => database.close());

  test(
    'pushes pending changes, pulls only account records and stores sync time',
    () async {
      final local = await repository.insert(
        QrRecord.created(content: 'local pending record'),
      );
      final remote = QrRecord.created(content: 'record from another device')
          .withRevision(2);
      transport.snapshot = QrSyncSnapshot(
        records: [remote],
        tombstones: const {},
      );

      await service.enable(
        ownerId: 'user-a',
        importExistingLocalData: false,
        consentGranted: true,
      );
      final report = await service.syncOnce('user-a');

      expect(report.applied, 1);
      expect(transport.appliedOwner, 'user-a');
      expect((await repository.findById(local.id))?.revision, 1);
      expect((await repository.findById(remote.id))?.content, remote.content);
      expect(await outbox.pendingCount('user-a'), 0);
      expect(await service.lastSyncAt('user-a'), isNotNull);

      final ownerB = SyncOwnerContext()..update('user-b');
      final repositoryB = SqliteQrRecordRepository(
        database,
        syncOwnerContext: ownerB,
      );
      expect(await repositoryB.listLatest(), isEmpty);
    },
  );

  test('imports only eligible legacy records after explicit consent', () async {
    final legacyRepository = SqliteQrRecordRepository(database);
    final first = await legacyRepository.insert(
      QrRecord.created(content: 'legacy one'),
    );
    final second = await legacyRepository.insert(
      QrRecord.created(content: 'legacy two'),
    );

    final imported = await service.importLocalRecords(
      ownerId: 'user-a',
      consentGranted: true,
    );

    expect(imported, 2);
    expect((await repository.listLatest()).map((record) => record.id).toSet(), {
      first.id,
      second.id,
    });
    expect(await outbox.pendingCount('user-a'), 2);
    expect(await legacyRepository.listLatest(), isEmpty);
  });

  test(
    'applies account tombstones without touching another account records',
    () async {
      final owned = QrRecord.created(content: 'owned record').withRevision(1);
      await repository.applyRemoteRecord(owned, ownerId: 'user-a');
      transport.snapshot = QrSyncSnapshot(
        records: const [],
        tombstones: {owned.id: 2},
      );

      await service.enable(
        ownerId: 'user-a',
        importExistingLocalData: false,
        consentGranted: true,
      );
      await service.syncOnce('user-a');

      expect(await repository.findById(owned.id), isNull);
    },
  );
}

class _FakePullTransport implements QrSyncPullTransport {
  QrSyncSnapshot snapshot = const QrSyncSnapshot(records: [], tombstones: {});
  String? appliedOwner;

  @override
  Future<List<QrSyncApplyResult>> applyBatch(
    String ownerId,
    List<QrSyncMutation> mutations,
  ) async {
    appliedOwner = ownerId;
    return mutations
        .map(
          (mutation) => QrSyncApplyResult(
            mutation.idempotencyKey,
            QrSyncApplyStatus.applied,
            revision: 1,
            recordId: mutation.recordId,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<QrSyncSnapshot> fetchSnapshot(String ownerId) async => snapshot;
}
