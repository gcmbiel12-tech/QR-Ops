import 'package:idb_shim/idb.dart';
import 'package:uuid/uuid.dart';

import '../domain/qr_record.dart';
import '../domain/qr_record_repository.dart';
import '../domain/qr_sync_contract.dart';
import '../domain/sync_owner_context.dart';

const _syncUuid = Uuid();

class IndexedDbQrRecordRepository
    implements QrRecordRepository, QrSyncLocalStore {
  IndexedDbQrRecordRepository({
    required this.factory,
    this.databaseName = defaultDatabaseName,
    this.syncOwnerContext,
  });

  static const defaultDatabaseName = 'qr_ops_history';
  static const _databaseVersion = 4;
  static const _storeName = 'qr_records';
  static const _outboxStoreName = 'qr_sync_outbox';

  final IdbFactory factory;
  final String databaseName;
  final SyncOwnerContext? syncOwnerContext;
  Future<Database>? _database;

  Future<Database> _openDatabase() async {
    final current = _database;
    if (current != null) return current;
    final opening = factory.open(
      databaseName,
      version: _databaseVersion,
      onUpgradeNeeded: (event) {
        if (event.oldVersion < 1) {
          event.database.createObjectStore(_storeName, keyPath: 'id');
        }
        if (event.oldVersion < 2) {
          event.database.createObjectStore(
            _outboxStoreName,
            keyPath: 'storage_key',
          );
        }
      },
    );
    _database = opening;
    try {
      return await opening;
    } on Object {
      if (identical(_database, opening)) _database = null;
      rethrow;
    }
  }

  @override
  Future<QrRecord> insert(QrRecord record) async {
    if (record.id.trim().isEmpty) {
      throw ArgumentError.value(record.id, 'record.id');
    }
    if (record.content.trim().isEmpty) {
      throw ArgumentError.value(record.content, 'record.content');
    }
    final owner = syncOwnerContext?.userId;
    final database = await _openDatabase();
    final transaction = database.transaction([
      _storeName,
      _outboxStoreName,
    ], idbModeReadWrite);
    try {
      await transaction
          .objectStore(_storeName)
          .add(_toRow(record, ownerId: owner));
      if (owner != null && record.operation != QrRecordOperation.ocr) {
        final base = await _nextBaseRevision(
          transaction,
          owner,
          record.id,
          record.revision,
        );
        await _enqueue(
          transaction,
          owner: owner,
          record: record,
          type: QrSyncMutationType.upsert,
          baseRevision: base,
        );
      }
      await transaction.completed;
      return record;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<List<QrRecord>> listLatest({int limit = 100}) async {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadOnly);
    try {
      final owner = syncOwnerContext?.userId;
      final rows = await transaction.objectStore(_storeName).getAll();
      await transaction.completed;
      final records =
          rows
              .where((row) => _belongsToOwner(row, owner))
              .map(_fromRow)
              .toList(growable: false)
            ..sort((a, b) {
              final byDate = b.createdAt.compareTo(a.createdAt);
              return byDate == 0 ? b.id.compareTo(a.id) : byDate;
            });
      return List.unmodifiable(records.take(limit));
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<QrRecord?> findById(String id) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadOnly);
    try {
      final owner = syncOwnerContext?.userId;
      final row = await transaction.objectStore(_storeName).getObject(id);
      await transaction.completed;
      return row == null || !_belongsToOwner(row, owner) ? null : _fromRow(row);
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<bool> deleteById(String id) async {
    final database = await _openDatabase();
    final transaction = database.transaction([
      _storeName,
      _outboxStoreName,
    ], idbModeReadWrite);
    final records = transaction.objectStore(_storeName);
    final owner = syncOwnerContext?.userId;
    try {
      final existing = await records.getObject(id);
      if (existing == null || !_belongsToOwner(existing, owner)) {
        await transaction.completed;
        return false;
      }
      final record = _fromRow(existing);
      if (owner != null && record.operation != QrRecordOperation.ocr) {
        final base = await _nextBaseRevision(
          transaction,
          owner,
          record.id,
          record.revision,
        );
        await _enqueue(
          transaction,
          owner: owner,
          recordId: record.id,
          type: QrSyncMutationType.delete,
          baseRevision: base,
          changedAt: DateTime.now().toUtc(),
        );
      }
      await records.delete(id);
      await transaction.completed;
      return true;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<bool> updateById(QrRecord record) async {
    final database = await _openDatabase();
    final transaction = database.transaction([
      _storeName,
      _outboxStoreName,
    ], idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    final owner = syncOwnerContext?.userId;
    try {
      final existing = await store.getObject(record.id);
      if (existing == null || !_belongsToOwner(existing, owner)) {
        await transaction.completed;
        return false;
      }
      final old = _fromRow(existing);
      final preserved = record.withRevision(old.revision);
      await store.put(_toRow(preserved, ownerId: owner));
      if (owner != null && preserved.operation != QrRecordOperation.ocr) {
        final base = await _nextBaseRevision(
          transaction,
          owner,
          preserved.id,
          old.revision,
        );
        await _enqueue(
          transaction,
          owner: owner,
          record: preserved,
          type: QrSyncMutationType.upsert,
          baseRevision: base,
        );
      }
      await transaction.completed;
      return true;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<int> pruneReadHistoryBefore(DateTime cutoffUtc) async {
    final database = await _openDatabase();
    final transaction = database.transaction([
      _storeName,
      _outboxStoreName,
    ], idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    var deleted = 0;
    try {
      final rows = await store.getAll();
      final cutoffMs = cutoffUtc.toUtc().millisecondsSinceEpoch;
      final owner = syncOwnerContext?.userId;
      for (final value in rows) {
        final row = Map<Object?, Object?>.from(value as Map);
        if (_belongsToOwner(row, owner) &&
            row['operation_type'] == 'read' &&
            row['created_at_ms'] is num &&
            (row['created_at_ms'] as num) < cutoffMs) {
          final record = _fromRow(row);
          if (owner != null) {
            final base = await _nextBaseRevision(
              transaction,
              owner,
              record.id,
              record.revision,
            );
            await _enqueue(
              transaction,
              owner: owner,
              recordId: record.id,
              type: QrSyncMutationType.delete,
              baseRevision: base,
            );
          }
          await store.delete(record.id);
          deleted++;
        }
      }
      await transaction.completed;
      return deleted;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<int> deleteAllReadHistory() async {
    final database = await _openDatabase();
    final transaction = database.transaction([
      _storeName,
      _outboxStoreName,
    ], idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    var deleted = 0;
    try {
      final rows = await store.getAll();
      final owner = syncOwnerContext?.userId;
      for (final value in rows) {
        final row = Map<Object?, Object?>.from(value as Map);
        if (_belongsToOwner(row, owner) && row['operation_type'] == 'read') {
          final record = _fromRow(row);
          if (owner != null) {
            final base = await _nextBaseRevision(
              transaction,
              owner,
              record.id,
              record.revision,
            );
            await _enqueue(
              transaction,
              owner: owner,
              recordId: record.id,
              type: QrSyncMutationType.delete,
              baseRevision: base,
            );
          }
          await store.delete(record.id);
          deleted++;
        }
      }
      await transaction.completed;
      return deleted;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  Future<int?> _nextBaseRevision(
    Transaction transaction,
    String owner,
    String recordId,
    int revision,
  ) async {
    final rows = await transaction.objectStore(_outboxStoreName).getAll();
    final pendingUpserts = rows.where((value) {
      final row = Map<Object?, Object?>.from(value as Map);
      return row['owner_id'] == owner &&
          row['record_id'] == recordId &&
          row['status'] == 'pending' &&
          row['mutation_type'] == 'upsert';
    }).length;
    return revision == 0 && pendingUpserts == 0
        ? null
        : revision + pendingUpserts;
  }

  Future<void> _enqueue(
    Transaction transaction, {
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
    final existingRows = await transaction
        .objectStore(_outboxStoreName)
        .getAll();
    var previousMs = -1;
    for (final value in existingRows) {
      final row = Map<Object?, Object?>.from(value as Map);
      if (row['owner_id'] == owner &&
          row['record_id'] == (recordId ?? record!.id) &&
          row['created_at_ms'] is num) {
        final candidate = (row['created_at_ms'] as num).toInt();
        if (candidate > previousMs) previousMs = candidate;
      }
    }
    final now = DateTime.fromMillisecondsSinceEpoch(
      previousMs < 0
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
    await transaction.objectStore(_outboxStoreName).add({
      ...mutation.toStorageMap(),
      'storage_key': '$owner::${mutation.idempotencyKey}',
    });
  }

  @override
  Future<List<QrRecord>> listUnownedRecords({
    required String ownerId,
    int limit = 1000,
  }) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final normalized = ownerId.trim();
    if (normalized.isEmpty) throw ArgumentError.value(ownerId, 'ownerId');
    final database = await _openDatabase();
    final transaction = database.transaction([
      _storeName,
      _outboxStoreName,
    ], idbModeReadOnly);
    try {
      final rows = await transaction.objectStore(_storeName).getAll();
      final outboxRows = await transaction
          .objectStore(_outboxStoreName)
          .getAll();
      await transaction.completed;
      final blockedIds = _recordIdsOwnedByOther(outboxRows, normalized);
      final records =
          rows
              .where((value) {
                if (!_belongsToOwner(value, null) ||
                    blockedIds.contains(_rowId(value))) {
                  return false;
                }
                final row = Map<Object?, Object?>.from(value as Map);
                return ((row['revision'] as num?)?.toInt() ?? 0) == 0 &&
                    row['operation_type'] != 'ocr';
              })
              .map(_fromRow)
              .toList(growable: false)
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List.unmodifiable(records.take(limit));
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<int> claimUnownedRecords(
    String ownerId, {
    required Set<String> recordIds,
  }) async {
    final normalized = ownerId.trim();
    if (normalized.isEmpty) throw ArgumentError.value(ownerId, 'ownerId');
    final allowedIds = recordIds.where((id) => id.trim().isNotEmpty).toSet();
    if (allowedIds.isEmpty) return 0;
    final database = await _openDatabase();
    final transaction = database.transaction([
      _storeName,
      _outboxStoreName,
    ], idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    var claimed = 0;
    try {
      final rows = await store.getAll();
      final outboxRows = await transaction
          .objectStore(_outboxStoreName)
          .getAll();
      final blockedIds = _recordIdsOwnedByOther(outboxRows, normalized);
      for (final value in rows) {
        final id = _rowId(value);
        if (!_belongsToOwner(value, null) ||
            id == null ||
            !allowedIds.contains(id) ||
            blockedIds.contains(id)) {
          continue;
        }
        final row = Map<Object?, Object?>.from(value as Map);
        if (((row['revision'] as num?)?.toInt() ?? 0) != 0 ||
            row['operation_type'] == 'ocr') {
          continue;
        }
        row['owner_id'] = normalized;
        await store.put(row);
        claimed++;
      }
      await transaction.completed;
      return claimed;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<int> deleteAllForOwner(String ownerId) async {
    final normalized = ownerId.trim();
    if (normalized.isEmpty) throw ArgumentError.value(ownerId, 'ownerId');
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    var deleted = 0;
    try {
      final rows = await store.getAll();
      for (final value in rows) {
        if (!_belongsToOwner(value, normalized)) continue;
        final id = _rowId(value);
        if (id == null) continue;
        await store.delete(id);
        deleted++;
      }
      await transaction.completed;
      return deleted;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<void> applyRemoteRecord(
    QrRecord record, {
    required String ownerId,
  }) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    try {
      final owner = ownerId.trim();
      if (owner.isEmpty)
        throw StateError('A sessão é necessária para aplicar dados remotos.');
      final existing = await store.getObject(record.id);
      if (existing != null && !_belongsToOwner(existing, owner)) {
        final row = Map<Object?, Object?>.from(existing as Map);
        final local = _fromRow(existing);
        if (row['owner_id'] != null ||
            (local.revision == 0 && !_sameRecordPayload(local, record))) {
          throw StateError(
            'O registro remoto conflita com um registro local de outra origem.',
          );
        }
      }
      if (existing != null && _fromRow(existing).revision > record.revision) {
        await transaction.completed;
        return;
      }
      await store.put(_toRow(record, ownerId: owner));
      await transaction.completed;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<void> applyRemoteDelete(
    String recordId, {
    required int revision,
    required String ownerId,
  }) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    try {
      final owner = ownerId.trim();
      if (owner.isEmpty)
        throw StateError('A sessão é necessária para aplicar dados remotos.');
      final existing = await store.getObject(recordId);
      if (existing != null) {
        final row = Map<Object?, Object?>.from(existing as Map);
        final local = _fromRow(existing);
        if ((_belongsToOwner(existing, owner) ||
                (row['owner_id'] == null && local.revision > 0)) &&
            local.revision <= revision) {
          await store.delete(recordId);
        }
      }
      await transaction.completed;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<void> setRevision(
    String id,
    int revision, {
    required String ownerId,
  }) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    try {
      final owner = ownerId.trim();
      final existing = await store.getObject(id);
      if (existing != null &&
          owner.isNotEmpty &&
          _belongsToOwner(existing, owner)) {
        final row = Map<Object?, Object?>.from(existing as Map)
          ..['revision'] = revision;
        await store.put(row);
      }
      await transaction.completed;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  Future<void> close() async {
    final opening = _database;
    _database = null;
    if (opening == null) return;
    (await opening).close();
  }

  Future<void> deleteDatabase() async {
    await close();
    await factory.deleteDatabase(databaseName);
  }

  Future<void> _finishAfterFailure(Transaction transaction) async {
    try {
      await transaction.completed;
    } on Object {
      // Preserve the original operation error while observing transaction failure.
    }
  }

  Map<String, Object?> _toRow(QrRecord record, {String? ownerId}) => {
    'id': record.id,
    'owner_id': ownerId,
    'operation_type': switch (record.operation) {
      QrRecordOperation.create => 'create',
      QrRecordOperation.read => 'read',
      QrRecordOperation.ocr => 'ocr',
    },
    'symbology': record.symbology,
    'content_type': record.contentType,
    'content': record.content,
    'name': record.name,
    'description': record.description,
    'created_at_ms': record.createdAt.toUtc().millisecondsSinceEpoch,
    'revision': record.revision,
  };

  Set<String> _recordIdsOwnedByOther(List<Object> rows, String ownerId) {
    final blocked = <String>{};
    for (final value in rows) {
      if (value is! Map) continue;
      final row = Map<Object?, Object?>.from(value);
      final recordId = row['record_id'];
      if (row['owner_id'] != ownerId && recordId is String) {
        blocked.add(recordId);
      }
    }
    return blocked;
  }

  String? _rowId(Object value) {
    if (value is! Map) return null;
    final id = Map<Object?, Object?>.from(value)['id'];
    return id is String ? id : null;
  }

  bool _sameRecordPayload(QrRecord a, QrRecord b) =>
      a.id == b.id &&
      a.operation == b.operation &&
      a.symbology == b.symbology &&
      a.contentType == b.contentType &&
      a.content == b.content &&
      a.name == b.name &&
      a.description == b.description &&
      a.createdAt.toUtc().millisecondsSinceEpoch ==
          b.createdAt.toUtc().millisecondsSinceEpoch;

  bool _belongsToOwner(Object value, String? owner) {
    if (value is! Map) return false;
    final row = Map<Object?, Object?>.from(value);
    return row['owner_id'] == owner;
  }

  QrRecord _fromRow(Object value) {
    if (value is! Map) {
      throw const FormatException('Registro inválido no histórico IndexedDB.');
    }
    final row = Map<Object?, Object?>.from(value);
    final operation = switch (row['operation_type']) {
      'create' => QrRecordOperation.create,
      'read' => QrRecordOperation.read,
      'ocr' => QrRecordOperation.ocr,
      final stored => throw FormatException(
        'Operação desconhecida no histórico: $stored',
      ),
    };
    final timestamp = row['created_at_ms'];
    if (timestamp is! num) {
      throw const FormatException('Data inválida no histórico IndexedDB.');
    }
    return QrRecord(
      id: _requiredString(row, 'id'),
      operation: operation,
      symbology: _requiredString(row, 'symbology'),
      contentType: _requiredString(row, 'content_type'),
      content: _requiredString(row, 'content'),
      name: row['name'] is String ? row['name'] as String : '',
      description: row['description'] is String
          ? row['description'] as String
          : '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        timestamp.toInt(),
        isUtc: true,
      ),
      revision: row['revision'] is num ? (row['revision'] as num).toInt() : 0,
    );
  }

  String _requiredString(Map<Object?, Object?> row, String key) {
    final value = row[key];
    if (value is! String) {
      throw FormatException('Campo inválido no histórico IndexedDB: $key.');
    }
    return value;
  }
}
