import 'package:shared_preferences/shared_preferences.dart';

import '../domain/qr_record.dart';
import '../domain/qr_record_repository.dart';
import '../domain/qr_sync_contract.dart';

class QrSyncService {
  QrSyncService({
    required this.localRepository,
    required this.outbox,
    required this.transport,
  });

  final QrRecordRepository localRepository;
  final PersistentQrSyncOutbox outbox;
  final QrSyncTransport transport;

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

  Future<void> disable(String ownerId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey(ownerId), false);
  }

  /// Explicitly authorizes import of existing local records. Stable import keys
  /// make interrupted/repeated imports safe without changing local records.
  Future<int> importLocalRecords({
    required String ownerId,
    required bool consentGranted,
  }) async {
    if (ownerId.trim().isEmpty) throw StateError('É necessária uma conta autenticada.');
    if (!consentGranted) throw StateError('A importação exige consentimento explícito.');

    final records = await localRepository.listLatest(limit: 1000);
    final existingOperations = await outbox.allForOwner(ownerId);
    final queuedRecordIds = existingOperations.map((item) => item.recordId).toSet();
    var enqueued = 0;
    for (final record in records) {
      if (record.revision > 0 || queuedRecordIds.contains(record.id)) continue;
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
    if (ownerId.trim().isEmpty) throw StateError('É necessária uma conta autenticada.');
    if (!consentGranted) throw StateError('Ativar a sincronização exige confirmação explícita.');
    if (importExistingLocalData) {
      await importLocalRecords(ownerId: ownerId, consentGranted: true);
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey(ownerId), true);
    await preferences.setBool('qr_ops_sync_paused_$ownerId', false);
  }

  Future<int> pendingCount(String ownerId) => outbox.pendingCount(ownerId);

  Future<QrSyncReport> syncOnce(String ownerId) async {
    if (ownerId.trim().isEmpty) throw StateError('É necessária uma conta autenticada.');
    if (!await isEnabled(ownerId) || await isPaused(ownerId)) {
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
          await (localRepository as QrSyncLocalStore).setRevision(id, revision);
        }
      },
    );
    final report = await coordinator.syncPending(
      currentUserId: ownerId,
      consentGranted: true,
    );
    // Remote pull is intentionally not applied until the local repository has
    // owner-scoped rows. The current local schema is device-global; merging a
    // second account here would expose its synced records after account switch.
    // QrSyncPullTransport is implemented, but activation is gated on that migration.
    return report;
  }

  Future<List<QrRecord>> localRecords() => localRepository.listLatest(limit: 1000);
}
