import 'dart:convert';

import 'qr_record.dart';

enum QrSyncMutationType { upsert, delete }

enum QrSyncApplyStatus { applied, alreadyApplied, conflict, retryableFailure }

/// Durable outbox item. Keys are stable across retries and owner-scoped.
class QrSyncMutation {
  const QrSyncMutation({
    required this.ownerId,
    required this.recordId,
    required this.idempotencyKey,
    required this.type,
    required this.changedAt,
    this.record,
    this.baseRevision,
    this.attemptCount = 0,
    this.lastError,
    this.createdAt,
    this.lastAttemptAt,
    this.isConflict = false,
  }) : assert(type == QrSyncMutationType.delete || record != null),
       assert(type == QrSyncMutationType.upsert || record == null),
       assert(baseRevision == null || baseRevision >= 0);

  final String ownerId;
  final String recordId;
  final String idempotencyKey;
  final QrSyncMutationType type;
  final DateTime changedAt;
  final QrRecord? record;
  final int? baseRevision;
  final int attemptCount;
  final String? lastError;
  final DateTime? createdAt;
  final DateTime? lastAttemptAt;
  final bool isConflict;

  Map<String, Object?> toStorageMap() => {
    'owner_id': ownerId,
    'idempotency_key': idempotencyKey,
    'record_id': recordId,
    'mutation_type': type.name,
    'payload_json': record == null ? null : jsonEncode(_recordToJson(record!)),
    'base_revision': baseRevision,
    'changed_at_ms': changedAt.toUtc().millisecondsSinceEpoch,
    'status': isConflict ? 'conflict' : 'pending',
    'attempt_count': attemptCount,
    'last_error': lastError,
    'created_at_ms': (createdAt ?? changedAt).toUtc().millisecondsSinceEpoch,
    'last_attempt_at_ms': lastAttemptAt?.toUtc().millisecondsSinceEpoch,
  };

  factory QrSyncMutation.fromStorageMap(Map<Object?, Object?> row) {
    final type = switch (row['mutation_type']) {
      'upsert' => QrSyncMutationType.upsert,
      'delete' => QrSyncMutationType.delete,
      final value => throw FormatException('Tipo de mutação inválido: $value'),
    };
    final payload = row['payload_json'];
    QrRecord? record;
    if (payload is String && payload.isNotEmpty) {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Payload da fila inválido.');
      }
      record = _recordFromJson(decoded);
    }
    final changedAtMs = row['changed_at_ms'];
    final createdAtMs = row['created_at_ms'];
    if (changedAtMs is! num || createdAtMs is! num) {
      throw const FormatException('Datas inválidas na fila de sincronização.');
    }
    final lastAttemptMs = row['last_attempt_at_ms'];
    final baseRevision = row['base_revision'];
    final attempts = row['attempt_count'];
    return QrSyncMutation(
      ownerId: _requiredString(row, 'owner_id'),
      recordId: _requiredString(row, 'record_id'),
      idempotencyKey: _requiredString(row, 'idempotency_key'),
      type: type,
      changedAt: DateTime.fromMillisecondsSinceEpoch(
        changedAtMs.toInt(),
        isUtc: true,
      ),
      record: record,
      baseRevision: baseRevision is num ? baseRevision.toInt() : null,
      attemptCount: attempts is num ? attempts.toInt() : 0,
      lastError: row['last_error'] is String ? row['last_error'] as String : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        createdAtMs.toInt(),
        isUtc: true,
      ),
      lastAttemptAt: lastAttemptMs is num
          ? DateTime.fromMillisecondsSinceEpoch(lastAttemptMs.toInt(), isUtc: true)
          : null,
      isConflict: row['status'] == 'conflict',
    );
  }
}

String _requiredString(Map<Object?, Object?> row, String key) {
  final value = row[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Campo inválido na fila de sincronização: $key.');
  }
  return value;
}

Map<String, Object?> _recordToJson(QrRecord record) => {
  'id': record.id,
  'operation': record.operation.name,
  'symbology': record.symbology,
  'content_type': record.contentType,
  'content': record.content,
  'name': record.name,
  'description': record.description,
  'created_at': record.createdAt.toUtc().toIso8601String(),
  'revision': record.revision,
};

QrRecord _recordFromJson(Map<String, dynamic> row) => QrRecord(
  id: row['id'] as String,
  operation: switch (row['operation']) {
    'create' => QrRecordOperation.create,
    'read' => QrRecordOperation.read,
    final value => throw FormatException('Operação inválida na fila: $value'),
  },
  symbology: row['symbology'] as String,
  contentType: row['content_type'] as String,
  content: row['content'] as String,
  name: row['name'] as String? ?? '',
  description: row['description'] as String? ?? '',
  createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
  revision: (row['revision'] as num?)?.toInt() ?? 0,
);

class QrSyncApplyResult {
  const QrSyncApplyResult(
    this.idempotencyKey,
    this.status, {
    this.revision,
    this.message,
    this.recordId,
  });

  final String idempotencyKey;
  final QrSyncApplyStatus status;
  final int? revision;
  final String? message;
  final String? recordId;
}

abstract interface class QrSyncOutbox {
  Future<List<QrSyncMutation>> pendingForOwner(
    String ownerId, {
    int limit = 100,
  });
  Future<void> acknowledge(String ownerId, Set<String> idempotencyKeys);
}

abstract interface class PersistentQrSyncOutbox implements QrSyncOutbox {
  Future<void> enqueue(QrSyncMutation mutation);
  Future<void> recordAttempt(
    String ownerId,
    Set<String> idempotencyKeys, {
    required DateTime attemptedAt,
    required String? error,
  });
  Future<void> markConflicts(String ownerId, Set<String> idempotencyKeys);
  Future<List<QrSyncMutation>> allForOwner(String ownerId);
  Future<int> pendingCount(String ownerId);
}

abstract interface class QrSyncTransport {
  /// Server must apply the batch transactionally and enforce auth.uid() ownership.
  Future<List<QrSyncApplyResult>> applyBatch(
    String ownerId,
    List<QrSyncMutation> mutations,
  );
}

class QrSyncSnapshot {
  const QrSyncSnapshot({required this.records, required this.tombstones});

  final List<QrRecord> records;
  final Map<String, int> tombstones;
}

abstract interface class QrSyncPullTransport implements QrSyncTransport {
  Future<QrSyncSnapshot> fetchSnapshot(String ownerId);
}

abstract interface class QrSyncLocalStore {
  Future<void> applyRemoteRecord(QrRecord record);
  Future<void> applyRemoteDelete(String recordId, {required int revision});
  Future<void> setRevision(String recordId, int revision);
}

class QrSyncReport {
  const QrSyncReport({
    required this.applied,
    required this.conflicts,
    required this.deferred,
  });

  final int applied;
  final int conflicts;
  final int deferred;
}

class QrSyncCoordinator {
  const QrSyncCoordinator({
    required this.outbox,
    required this.transport,
    this.onApplied,
  });

  final QrSyncOutbox outbox;
  final QrSyncTransport transport;
  final Future<void> Function(QrSyncApplyResult result)? onApplied;

  Future<QrSyncReport> syncPending({
    required String currentUserId,
    required bool consentGranted,
    int batchSize = 100,
  }) async {
    if (currentUserId.trim().isEmpty) {
      throw StateError('Uma sessão autenticada é obrigatória para sincronizar.');
    }
    if (!consentGranted) {
      throw StateError('A sincronização exige consentimento explícito.');
    }
    if (batchSize < 1 || batchSize > 100) {
      throw ArgumentError.value(batchSize, 'batchSize', 'Use um valor entre 1 e 100.');
    }

    final pending = await outbox.pendingForOwner(currentUserId, limit: batchSize);
    if (pending.isEmpty) {
      return const QrSyncReport(applied: 0, conflicts: 0, deferred: 0);
    }
    final keys = <String>{};
    for (final mutation in pending) {
      if (mutation.ownerId != currentUserId) {
        throw StateError('A fila contém uma operação pertencente a outra conta.');
      }
      if (mutation.recordId.trim().isEmpty ||
          (mutation.type == QrSyncMutationType.upsert && mutation.record?.id != mutation.recordId) ||
          mutation.idempotencyKey.trim().isEmpty ||
          !keys.add(mutation.idempotencyKey)) {
        throw StateError('A fila contém chaves de idempotência inválidas ou duplicadas.');
      }
    }

    final now = DateTime.now().toUtc();
    if (outbox is PersistentQrSyncOutbox) {
      await (outbox as PersistentQrSyncOutbox).recordAttempt(
        currentUserId,
        keys,
        attemptedAt: now,
        error: null,
      );
    }

    late final List<QrSyncApplyResult> results;
    try {
      results = await transport.applyBatch(currentUserId, pending);
    } on Object catch (error) {
      if (outbox is PersistentQrSyncOutbox) {
        await (outbox as PersistentQrSyncOutbox).recordAttempt(
          currentUserId,
          keys,
          attemptedAt: now,
          error: error.runtimeType.toString(),
        );
      }
      return QrSyncReport(applied: 0, conflicts: 0, deferred: pending.length);
    }

    final expectedKeys = pending.map((item) => item.idempotencyKey).toSet();
    final resultKeys = results.map((item) => item.idempotencyKey).toSet();
    if (resultKeys.length != results.length ||
        resultKeys.length != expectedKeys.length ||
        !resultKeys.containsAll(expectedKeys)) {
      throw StateError('Resposta de sincronização incompleta ou inconsistente.');
    }

    final acknowledged = <String>{};
    final conflicted = <String>{};
    var applied = 0;
    var conflicts = 0;
    var deferred = 0;
    for (final result in results) {
      switch (result.status) {
        case QrSyncApplyStatus.applied:
        case QrSyncApplyStatus.alreadyApplied:
          acknowledged.add(result.idempotencyKey);
          applied++;
        case QrSyncApplyStatus.conflict:
          conflicted.add(result.idempotencyKey);
          conflicts++;
        case QrSyncApplyStatus.retryableFailure:
          deferred++;
      }
    }
    if (onApplied != null) {
      for (final result in results) {
        if ((result.status == QrSyncApplyStatus.applied ||
                result.status == QrSyncApplyStatus.alreadyApplied) &&
            result.revision != null) {
          await onApplied!(result);
        }
      }
    }
    if (acknowledged.isNotEmpty) {
      await outbox.acknowledge(currentUserId, acknowledged);
    }
    if (conflicted.isNotEmpty && outbox is PersistentQrSyncOutbox) {
      await (outbox as PersistentQrSyncOutbox).markConflicts(currentUserId, conflicted);
    }
    return QrSyncReport(applied: applied, conflicts: conflicts, deferred: deferred);
  }
}
