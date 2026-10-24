import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/qr_record.dart';
import '../domain/qr_record_repository.dart';
import '../domain/qr_sync_contract.dart';
import '../domain/sync_owner_context.dart';

const _syncUuid = Uuid();

class SqliteQrRecordRepository implements QrRecordRepository, QrSyncLocalStore {
  const SqliteQrRecordRepository(this._database, {this.syncOwnerContext});

  final Database _database;
  final SyncOwnerContext? syncOwnerContext;

  @override
  Future<QrRecord> insert(QrRecord record) async {
    if (record.id.isEmpty) throw ArgumentError.value(record.id, 'record.id');
    if (record.content.trim().isEmpty) {
      throw ArgumentError.value(record.content, 'record.content');
    }

    await _database.transaction((txn) async {
      await txn.insert(
        'qr_records',
        _toRow(record),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      final owner = syncOwnerContext?.userId;
      if (owner != null && record.operation != QrRecordOperation.ocr) {
        await _enqueue(
          txn,
          owner: owner,
          record: record,
          type: QrSyncMutationType.upsert,
          baseRevision: await _nextBaseRevision(
            txn,
            owner,
            record.id,
            record.revision,
          ),
        );
      }
    });
    return record;
  }

  @override
  Future<List<QrRecord>> listLatest({int limit = 100}) async {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final rows = await _database.query(
      'qr_records',
      orderBy: 'created_at_ms DESC, id DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<QrRecord?> findById(String id) async {
    final rows = await _database.query(
      'qr_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<bool> deleteById(String id) async {
    return _database.transaction((txn) async {
      final rows = await txn.query(
        'qr_records',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final record = _fromRow(rows.single);
      final owner = syncOwnerContext?.userId;
      if (owner != null && record.operation != QrRecordOperation.ocr) {
        final baseRevision = await _nextBaseRevision(
          txn,
          owner,
          record.id,
          record.revision,
        );
        await _enqueue(
          txn,
          owner: owner,
          record: null,
          recordId: record.id,
          type: QrSyncMutationType.delete,
          baseRevision: baseRevision,
          changedAt: DateTime.now().toUtc(),
        );
      }
      await txn.delete('qr_records', where: 'id = ?', whereArgs: [id]);
      return true;
    });
  }

  @override
  Future<bool> updateById(QrRecord record) async {
    return _database.transaction((txn) async {
      final rows = await txn.query(
        'qr_records',
        where: 'id = ?',
        whereArgs: [record.id],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final old = _fromRow(rows.single);
      final preserved = record.withRevision(old.revision);
      await txn.update(
        'qr_records',
        _toRow(preserved),
        where: 'id = ?',
        whereArgs: [record.id],
      );
      final owner = syncOwnerContext?.userId;
      if (owner != null && preserved.operation != QrRecordOperation.ocr) {
        await _enqueue(
          txn,
          owner: owner,
          record: preserved,
          type: QrSyncMutationType.upsert,
          baseRevision: await _nextBaseRevision(
            txn,
            owner,
            preserved.id,
            old.revision,
          ),
        );
      }
      return true;
    });
  }

  @override
  Future<int> pruneReadHistoryBefore(DateTime cutoffUtc) async {
    return _database.transaction((txn) async {
      final owner = syncOwnerContext?.userId;
      if (owner != null) {
        final rows = await txn.query(
          'qr_records',
          where: 'operation_type = ? AND created_at_ms < ?',
          whereArgs: ['read', cutoffUtc.toUtc().millisecondsSinceEpoch],
        );
        for (final row in rows) {
          final record = _fromRow(row);
          await _enqueue(
            txn,
            owner: owner,
            record: null,
            recordId: record.id,
            type: QrSyncMutationType.delete,
            baseRevision: await _nextBaseRevision(
              txn,
              owner,
              record.id,
              record.revision,
            ),
            changedAt: DateTime.now().toUtc(),
          );
        }
      }
      return txn.delete(
        'qr_records',
        where: 'operation_type = ? AND created_at_ms < ?',
        whereArgs: ['read', cutoffUtc.toUtc().millisecondsSinceEpoch],
      );
    });
  }

  @override
  Future<int> deleteAllReadHistory() async {
    return _database.transaction((txn) async {
      final owner = syncOwnerContext?.userId;
      if (owner != null) {
        final rows = await txn.query(
          'qr_records',
          where: 'operation_type = ?',
          whereArgs: ['read'],
        );
        for (final row in rows) {
          final record = _fromRow(row);
          await _enqueue(
            txn,
            owner: owner,
            record: null,
            recordId: record.id,
            type: QrSyncMutationType.delete,
            baseRevision: await _nextBaseRevision(
              txn,
              owner,
              record.id,
              record.revision,
            ),
            changedAt: DateTime.now().toUtc(),
          );
        }
      }
      return txn.delete(
        'qr_records',
        where: 'operation_type = ?',
        whereArgs: ['read'],
      );
    });
  }

  Future<int?> _nextBaseRevision(
    Transaction txn,
    String owner,
    String recordId,
    int revision,
  ) async {
    final rows = await txn.rawQuery(
      "SELECT COUNT(*) AS count FROM qr_sync_outbox WHERE owner_id = ? AND record_id = ? AND status = 'pending' AND mutation_type = 'upsert'",
      [owner, recordId],
    );
    final pendingUpserts = (rows.single['count'] as num).toInt();
    return revision == 0 && pendingUpserts == 0
        ? null
        : revision + pendingUpserts;
  }

  Future<void> _enqueue(
    Transaction txn, {
    required String owner,
    required QrSyncMutationType type,
    required int? baseRevision,
    QrRecord? record,
    String? recordId,
    DateTime? changedAt,
  }) async {
    final requestedMs = (changedAt ?? DateTime.now())
        .toUtc()
        .millisecondsSinceEpoch;
    final previousRows = await txn.rawQuery(
      'SELECT MAX(created_at_ms) AS last_ms FROM qr_sync_outbox WHERE owner_id = ? AND record_id = ?',
      [owner, recordId ?? record!.id],
    );
    final previousMs = previousRows.single['last_ms'] as int?;
    final now = DateTime.fromMillisecondsSinceEpoch(
      previousMs == null
          ? requestedMs
          : (requestedMs > previousMs ? requestedMs : previousMs + 1),
      isUtc: true,
    );
    final mutation = QrSyncMutation(
      ownerId: owner,
      recordId: recordId ?? record!.id,
      idempotencyKey: _syncUuid.v4(),
      type: type,
      changedAt: now,
      createdAt: now,
      record: record,
      baseRevision: baseRevision,
    );
    await txn.insert('qr_sync_outbox', mutation.toStorageMap());
  }

  @override
  Future<void> applyRemoteRecord(QrRecord record) async {
    await _database.transaction((txn) async {
      final rows = await txn.query(
        'qr_records',
        where: 'id = ?',
        whereArgs: [record.id],
        limit: 1,
      );
      if (rows.isNotEmpty && _fromRow(rows.single).revision > record.revision) {
        return;
      }
      await txn.insert(
        'qr_records',
        _toRow(record),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<void> applyRemoteDelete(
    String recordId, {
    required int revision,
  }) async {
    await _database.transaction((txn) async {
      final rows = await txn.query(
        'qr_records',
        where: 'id = ?',
        whereArgs: [recordId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      if (_fromRow(rows.single).revision <= revision) {
        await txn.delete('qr_records', where: 'id = ?', whereArgs: [recordId]);
      }
    });
  }

  @override
  Future<void> setRevision(String id, int revision) async {
    await _database.update(
      'qr_records',
      {'revision': revision},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Map<String, Object?> _toRow(QrRecord record) => {
    'id': record.id,
    'operation_type': _operationToStorage(record.operation),
    'symbology': record.symbology,
    'content_type': record.contentType,
    'content': record.content,
    'name': record.name,
    'description': record.description,
    'created_at_ms': record.createdAt.toUtc().millisecondsSinceEpoch,
    'revision': record.revision,
  };

  QrRecord _fromRow(Map<String, Object?> row) {
    final operation = switch (row['operation_type']) {
      'create' => QrRecordOperation.create,
      'read' => QrRecordOperation.read,
      'ocr' => QrRecordOperation.ocr,
      final value => throw FormatException(
        'Operação desconhecida no histórico: $value',
      ),
    };
    return QrRecord(
      id: row['id']! as String,
      operation: operation,
      symbology: row['symbology']! as String,
      contentType: row['content_type']! as String,
      content: row['content']! as String,
      name: row['name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at_ms']! as int,
        isUtc: true,
      ),
      revision: row['revision'] as int? ?? 0,
    );
  }

  String _operationToStorage(QrRecordOperation operation) =>
      switch (operation) {
        QrRecordOperation.create => 'create',
        QrRecordOperation.read => 'read',
        QrRecordOperation.ocr => 'ocr',
      };
}
