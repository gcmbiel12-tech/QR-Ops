import 'package:shared_preferences/shared_preferences.dart';

import '../domain/qr_record.dart';
import '../domain/qr_record_repository.dart';
import '../domain/qr_sync_contract.dart';
import '../domain/sync_owner_context.dart';

class QrSyncService {
  QrSyncService({
    required this.localRepository,
    required this.outbox,
    required this.transport,
    required this.ownerContext,
  });

  final QrRecordRepository localRepository;
  final PersistentQrSyncOutbox outbox;
  final QrSyncTransport transport;
  final SyncOwnerContext ownerContext;

  void _requireCurrentOwner(String ownerId) {
    if (ownerContext.userId != ownerId) {
      throw StateError(
        'A conta ativa mudou durante a operação. Tente novamente.',
      );
    }
  }

  String _enabledKey(String ownerId) => 'qr_ops_sync_enabled_$ownerId';

  Future<bool> isEnabled(String ownerId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey(ownerId)) ?? false;
  }

  Future<void> setPaused(String ownerId, bool paused) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('qr_ops_sync_paused_$ownerId', paused);
  }

  Future<bool> isPaused(String ownerId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool('qr_ops_sync_paused_$ownerId') ?? false;
  }

  Future<DateTime?> lastSyncAt(String ownerId) async {
    final preferences = await SharedPreferences.getInstance();
    final milliseconds = preferences.getInt('qr_ops_last_sync_$ownerId');
    if (milliseconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  Future<void> disable(String ownerId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey(ownerId), false);
  }

  /// Explicitly claims eligible unowned records for this account, then queues
  /// eligible QR records with stable keys so interrupted imports can resume.
  Future<int> importLocalRecords({
    required String ownerId,
    required bool consentGranted,
  }) async {
    if (ownerId.trim().isEmpty)
      throw StateError('É necessária uma conta autenticada.');
    _requireCurrentOwner(ownerId);
    if (!consentGranted)
      throw StateError('A importação exige consentimento explícito.');

    final records = await localRecordsForImport(ownerId);
    _requireCurrentOwner(ownerId);
    if (localRepository is QrSyncLocalStore) {
      await (localRepository as QrSyncLocalStore).claimUnownedRecords(
        ownerId,
        recordIds: records.map((record) => record.id).toSet(),
      );
      _requireCurrentOwner(ownerId);
    }
    final existingOperations = await outbox.allForOwner(ownerId);
    _requireCurrentOwner(ownerId);
    final queuedRecordIds = existingOperations
        .map((item) => item.recordId)
        .toSet();
    var enqueued = 0;
    for (final record in records) {
      _requireCurrentOwner(ownerId);
      if (record.operation == QrRecordOperation.ocr ||
          record.revision > 0 ||
          queuedRecordIds.contains(record.id)) {
        continue;
      }
      final now = DateTime.now().toUtc();
      final mutation = QrSyncMutation(
        ownerId: ownerId,
        recordId: record.id,
        idempotencyKey: 'import-$ownerId-${record.id}',
        type: QrSyncMutationType.upsert,
        changedAt: now,
        createdAt: now,
        record: record,
        baseRevision: null,
      );
      await outbox.enqueue(mutation);
      enqueued++;
    }
    return enqueued;
  }

  Future<void> enable({
    required String ownerId,
    required bool importExistingLocalData,
    required bool consentGranted,
  }) async {
    if (ownerId.trim().isEmpty)
      throw StateError('É necessária uma conta autenticada.');
    _requireCurrentOwner(ownerId);
    if (!consentGranted)
      throw StateError('Ativar a sincronização exige confirmação explícita.');
    if (importExistingLocalData) {
      await importLocalRecords(ownerId: ownerId, consentGranted: true);
    }
    _requireCurrentOwner(ownerId);
    final preferences = await SharedPreferences.getInstance();
    _requireCurrentOwner(ownerId);
    await preferences.setBool(_enabledKey(ownerId), true);
    await preferences.setBool('qr_ops_sync_paused_$ownerId', false);
  }

  Future<int> pendingCount(String ownerId) => outbox.pendingCount(ownerId);

  Future<QrSyncReport> syncOnce(String ownerId) async {
    if (ownerId.trim().isEmpty)
      throw StateError('É necessária uma conta autenticada.');
    _requireCurrentOwner(ownerId);
    final enabled = await isEnabled(ownerId);
    _requireCurrentOwner(ownerId);
    final paused = await isPaused(ownerId);
    _requireCurrentOwner(ownerId);
    if (!enabled || paused) {
      return const QrSyncReport(applied: 0, conflicts: 0, deferred: 0);
    }
    final coordinator = QrSyncCoordinator(
      outbox: outbox,
      transport: transport,
      onApplied: (result) async {
        final id = result.recordId;
        final revision = result.revision;
        if (id == null || revision == null) return;
        if (localRepository is QrSyncLocalStore) {
          await (localRepository as QrSyncLocalStore).setRevision(
            id,
            revision,
            ownerId: ownerId,
          );
        }
      },
    );
    final report = await coordinator.syncPending(
      currentUserId: ownerId,
      consentGranted: true,
    );
    _requireCurrentOwner(ownerId);
    if (transport is QrSyncPullTransport &&
        localRepository is QrSyncLocalStore) {
      final ownerOperations = await outbox.allForOwner(ownerId);
      _requireCurrentOwner(ownerId);
      final protectedRecordIds = ownerOperations
          .map((mutation) => mutation.recordId)
          .toSet();
      final snapshot = await (transport as QrSyncPullTransport).fetchSnapshot(
        ownerId,
      );
      _requireCurrentOwner(ownerId);
      final localStore = localRepository as QrSyncLocalStore;
      for (final record in snapshot.records) {
        if (protectedRecordIds.contains(record.id)) continue;
        _requireCurrentOwner(ownerId);
        await localStore.applyRemoteRecord(record, ownerId: ownerId);
      }
      for (final tombstone in snapshot.tombstones.entries) {
        if (protectedRecordIds.contains(tombstone.key)) continue;
        _requireCurrentOwner(ownerId);
        await localStore.applyRemoteDelete(
          tombstone.key,
          revision: tombstone.value,
          ownerId: ownerId,
        );
      }
    }
    if (report.deferred == 0) {
      _requireCurrentOwner(ownerId);
      final preferences = await SharedPreferences.getInstance();
      _requireCurrentOwner(ownerId);
      await preferences.setInt(
        'qr_ops_last_sync_$ownerId',
        DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    }
    return report;
  }

  Future<void> purgeLocalAccount(String ownerId) async {
    final normalized = ownerId.trim();
    if (normalized.isEmpty) throw ArgumentError.value(ownerId, 'ownerId');
    if (localRepository is QrSyncLocalStore) {
      await (localRepository as QrSyncLocalStore).deleteAllForOwner(normalized);
    }
    await outbox.deleteAllForOwner(normalized);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_enabledKey(normalized));
    await preferences.remove('qr_ops_sync_paused_$normalized');
    await preferences.remove('qr_ops_last_sync_$normalized');
  }

  Future<List<QrRecord>> localRecordsForImport(String ownerId) async {
    if (ownerId.trim().isEmpty) {
      throw StateError('É necessária uma conta autenticada.');
    }
    _requireCurrentOwner(ownerId);
    final records = await localRepository.listLatest(limit: 1000);
    _requireCurrentOwner(ownerId);
    if (localRepository is! QrSyncLocalStore) return records;
    final unowned = await (localRepository as QrSyncLocalStore)
        .listUnownedRecords(ownerId: ownerId, limit: 1000);
    _requireCurrentOwner(ownerId);
    final queuedOperations = await outbox.allForOwner(ownerId);
    _requireCurrentOwner(ownerId);
    final queuedIds = queuedOperations
        .map((mutation) => mutation.recordId)
        .toSet();
    final candidates = <String, QrRecord>{
      for (final record in records)
        if (record.operation != QrRecordOperation.ocr &&
            record.revision == 0 &&
            !queuedIds.contains(record.id))
          record.id: record,
      for (final record in unowned)
        if (record.operation != QrRecordOperation.ocr) record.id: record,
    }.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(candidates.take(1000));
  }
}
