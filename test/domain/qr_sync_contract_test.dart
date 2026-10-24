import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/domain/qr_sync_contract.dart';

void main() {
  test('requires explicit consent and an authenticated owner', () async {
    final coordinator = QrSyncCoordinator(
      outbox: _Outbox([]),
      transport: _Transport((_, _) => const []),
    );
    await expectLater(
      coordinator.syncPending(currentUserId: 'user-a', consentGranted: false),
      throwsStateError,
    );
    await expectLater(
      coordinator.syncPending(currentUserId: '', consentGranted: true),
      throwsStateError,
    );
  });

  test(
    'rejects a queue item owned by another account before transport',
    () async {
      final transport = _Transport((_, _) => const []);
      final coordinator = QrSyncCoordinator(
        outbox: _Outbox([_mutation('user-b', 'key-b')], filterOwner: false),
        transport: transport,
      );
      await expectLater(
        coordinator.syncPending(currentUserId: 'user-a', consentGranted: true),
        throwsStateError,
      );
      expect(transport.calls, 0);
    },
  );

  test('acknowledges applied and already-applied operations only', () async {
    final outbox = _Outbox([
      _mutation('user-a', 'key-a'),
      _mutation('user-a', 'key-b'),
      _mutation('user-a', 'key-c'),
    ]);
    final coordinator = QrSyncCoordinator(
      outbox: outbox,
      transport: _Transport(
        (owner, mutations) => [
          const QrSyncApplyResult('key-a', QrSyncApplyStatus.applied),
          const QrSyncApplyResult('key-b', QrSyncApplyStatus.alreadyApplied),
          const QrSyncApplyResult('key-c', QrSyncApplyStatus.conflict),
        ],
      ),
    );

    final report = await coordinator.syncPending(
      currentUserId: 'user-a',
      consentGranted: true,
    );

    expect(report.applied, 2);
    expect(report.conflicts, 1);
    expect(report.deferred, 0);
    expect(outbox.pending.map((item) => item.idempotencyKey), ['key-c']);
  });

  test('retains all operations after offline transport failure', () async {
    final outbox = _Outbox([
      _mutation('user-a', 'key-a'),
      _mutation('user-a', 'key-b'),
    ]);
    final coordinator = QrSyncCoordinator(
      outbox: outbox,
      transport: _Transport((_, _) => throw StateError('offline')),
    );

    final report = await coordinator.syncPending(
      currentUserId: 'user-a',
      consentGranted: true,
    );

    expect(report.deferred, 2);
    expect(outbox.pending, hasLength(2));
  });

  test(
    'rejects incomplete transport responses without acknowledging queue',
    () async {
      final outbox = _Outbox([_mutation('user-a', 'key-a')]);
      final coordinator = QrSyncCoordinator(
        outbox: outbox,
        transport: _Transport((_, _) => const []),
      );

      await expectLater(
        coordinator.syncPending(currentUserId: 'user-a', consentGranted: true),
        throwsStateError,
      );
      expect(outbox.pending, hasLength(1));
    },
  );
}

QrSyncMutation _mutation(String owner, String key) {
  final record = QrRecord(
    id: key,
    operation: QrRecordOperation.create,
    symbology: 'qr',
    contentType: 'text',
    content: 'local-only',
    createdAt: DateTime.utc(2026, 10, 23),
  );
  return QrSyncMutation(
    ownerId: owner,
    recordId: record.id,
    idempotencyKey: key,
    type: QrSyncMutationType.upsert,
    changedAt: DateTime.utc(2026, 10, 23),
    record: record,
  );
}

class _Outbox implements QrSyncOutbox {
  _Outbox(this.pending, {this.filterOwner = true});
  final List<QrSyncMutation> pending;
  final bool filterOwner;

  @override
  Future<List<QrSyncMutation>> pendingForOwner(
    String ownerId, {
    int limit = 100,
  }) async =>
      (filterOwner ? pending.where((item) => item.ownerId == ownerId) : pending)
          .take(limit)
          .toList();

  @override
  Future<void> acknowledge(String ownerId, Set<String> idempotencyKeys) async {
    pending.removeWhere(
      (item) =>
          item.ownerId == ownerId &&
          idempotencyKeys.contains(item.idempotencyKey),
    );
  }
}

class _Transport implements QrSyncTransport {
  _Transport(this.handler);
  final List<QrSyncApplyResult> Function(String, List<QrSyncMutation>) handler;
  int calls = 0;

  @override
  Future<List<QrSyncApplyResult>> applyBatch(
    String ownerId,
    List<QrSyncMutation> mutations,
  ) async {
    calls++;
    return handler(ownerId, mutations);
  }
}
