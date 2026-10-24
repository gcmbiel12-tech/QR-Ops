import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/qr_sync_contract.dart';

class SqliteQrSyncOutbox implements PersistentQrSyncOutbox {
  const SqliteQrSyncOutbox(this.database);

  final Database database;

  @override
  Future<void> enqueue(QrSyncMutation mutation) async {
    final row = mutation.toStorageMap();
    await database.transaction((txn) async {
      final existing = await txn.query(
        'qr_sync_outbox',
        where: 'owner_id = ? AND idempotency_key = ?',
        whereArgs: [mutation.ownerId, mutation.idempotencyKey],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final old = QrSyncMutation.fromStorageMap(existing.single);
        if (!_sameMutation(old, mutation)) {
          throw StateError('A chave idempotente já existe com outro conteúdo.');
        }
        return;
      }
      await txn.insert('qr_sync_outbox', row);
    });
  }

  @override
  Future<List<QrSyncMutation>> pendingForOwner(
    String ownerId, {
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 1000) throw ArgumentError.value(limit, 'limit');
    final rows = await database.query(
      'qr_sync_outbox',
      where: 'owner_id = ? AND status = ?',
      whereArgs: [ownerId, 'pending'],
      orderBy: 'created_at_ms ASC, idempotency_key ASC',
      limit: limit,
    );
    return rows
        .map((row) => QrSyncMutation.fromStorageMap(row))
        .toList(growable: false);
  }

  @override
  Future<void> acknowledge(String ownerId, Set<String> idempotencyKeys) async {
    if (idempotencyKeys.isEmpty) return;
    await database.transaction((txn) async {
      for (final key in idempotencyKeys) {
        await txn.delete(
          'qr_sync_outbox',
          where: 'owner_id = ? AND idempotency_key = ? AND status = ?',
          whereArgs: [ownerId, key, 'pending'],
        );
      }
    });
  }

  @override
  Future<void> recordAttempt(
    String ownerId,
    Set<String> idempotencyKeys, {
    required DateTime attemptedAt,
    required String? error,
  }) async {
    if (idempotencyKeys.isEmpty) return;
    await database.transaction((txn) async {
      for (final key in idempotencyKeys) {
        await txn.rawUpdate(
          'UPDATE qr_sync_outbox SET attempt_count = attempt_count + 1, last_attempt_at_ms = ?, last_error = ? WHERE owner_id = ? AND idempotency_key = ? AND status = ?',
          [
            attemptedAt.toUtc().millisecondsSinceEpoch,
            error,
            ownerId,
            key,
            'pending',
          ],
        );
      }
    });
  }

  @override
  Future<void> markConflicts(String ownerId, Set<String> idempotencyKeys) async {
    if (idempotencyKeys.isEmpty) return;
    await database.transaction((txn) async {
      for (final key in idempotencyKeys) {
        await txn.update(
          'qr_sync_outbox',
          {'status': 'conflict', 'last_error': 'revision_conflict'},
          where: 'owner_id = ? AND idempotency_key = ?',
          whereArgs: [ownerId, key],
        );
      }
    });
  }

  @override
  Future<List<QrSyncMutation>> allForOwner(String ownerId) async {
    final rows = await database.query(
      'qr_sync_outbox',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'created_at_ms ASC, idempotency_key ASC',
    );
    return rows.map(QrSyncMutation.fromStorageMap).toList(growable: false);
  }

  @override
  Future<int> pendingCount(String ownerId) async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM qr_sync_outbox WHERE owner_id = ? AND status = ?',
      [ownerId, 'pending'],
    );
    return (rows.single['count'] as num).toInt();
  }

  bool _sameMutation(QrSyncMutation a, QrSyncMutation b) {
    return a.ownerId == b.ownerId &&
        a.recordId == b.recordId &&
        a.type == b.type &&
        a.baseRevision == b.baseRevision &&
        jsonEncode(a.record == null ? null : a.toStorageMap()['payload_json']) ==
            jsonEncode(b.record == null ? null : b.toStorageMap()['payload_json']);
  }
}
