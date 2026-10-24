import 'dart:convert';

import 'package:idb_shim/idb.dart';

import '../domain/qr_sync_contract.dart';

class IndexedDbQrSyncOutbox implements PersistentQrSyncOutbox {
  IndexedDbQrSyncOutbox({
    required this.factory,
    this.databaseName = 'qr_ops_history',
  });

  static const _databaseVersion = 2;
  static const _storeName = 'qr_sync_outbox';

  final IdbFactory factory;
  final String databaseName;
  Future<Database>? _database;

  Future<Database> _openDatabase() async {
    final current = _database;
    if (current != null) return current;
    final opening = factory.open(
      databaseName,
      version: _databaseVersion,
      onUpgradeNeeded: (event) {
        if (event.oldVersion < 1) {
          event.database.createObjectStore('qr_records', keyPath: 'id');
        }
        if (event.oldVersion < 2) {
          event.database.createObjectStore(_storeName, keyPath: 'storage_key');
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
  Future<void> enqueue(QrSyncMutation mutation) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    final key = _storageKey(mutation.ownerId, mutation.idempotencyKey);
    try {
      final existing = await store.getObject(key);
      if (existing != null) {
        final old = QrSyncMutation.fromStorageMap(
          Map<Object?, Object?>.from(existing as Map),
        );
        if (!_sameMutation(old, mutation)) {
          throw StateError('A chave idempotente já existe com outro conteúdo.');
        }
      } else {
        await store.add({...mutation.toStorageMap(), 'storage_key': key});
      }
      await transaction.completed;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<List<QrSyncMutation>> pendingForOwner(
    String ownerId, {
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 1000) throw ArgumentError.value(limit, 'limit');
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadOnly);
    try {
      final rows = await transaction.objectStore(_storeName).getAll();
      await transaction.completed;
      final mutations = rows
          .map((row) => QrSyncMutation.fromStorageMap(
                Map<Object?, Object?>.from(row as Map),
              ))
          .where((mutation) => mutation.ownerId == ownerId && !mutation.isConflict)
          .toList()
        ..sort((a, b) {
          final byDate = (a.createdAt ?? a.changedAt).compareTo(
            b.createdAt ?? b.changedAt,
          );
          return byDate == 0
              ? a.idempotencyKey.compareTo(b.idempotencyKey)
              : byDate;
        });
      return List.unmodifiable(mutations.take(limit));
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<void> acknowledge(String ownerId, Set<String> idempotencyKeys) async {
    if (idempotencyKeys.isEmpty) return;
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    try {
      for (final key in idempotencyKeys) {
        final storageKey = _storageKey(ownerId, key);
        final existing = await store.getObject(storageKey);
        if (existing != null) {
          final mutation = QrSyncMutation.fromStorageMap(
            Map<Object?, Object?>.from(existing as Map),
          );
          if (mutation.ownerId == ownerId && !mutation.isConflict) {
            await store.delete(storageKey);
          }
        }
      }
      await transaction.completed;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<void> recordAttempt(
    String ownerId,
    Set<String> idempotencyKeys, {
    required DateTime attemptedAt,
    required String? error,
  }) async {
    if (idempotencyKeys.isEmpty) return;
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    try {
      for (final key in idempotencyKeys) {
        final storageKey = _storageKey(ownerId, key);
        final existing = await store.getObject(storageKey);
        if (existing == null) continue;
        final row = Map<Object?, Object?>.from(existing as Map);
        if (row['owner_id'] != ownerId || row['status'] == 'conflict') continue;
        row['attempt_count'] = ((row['attempt_count'] as num?)?.toInt() ?? 0) + 1;
        row['last_attempt_at_ms'] = attemptedAt.toUtc().millisecondsSinceEpoch;
        row['last_error'] = error;
        await store.put({...row, 'storage_key': storageKey});
      }
      await transaction.completed;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<void> markConflicts(String ownerId, Set<String> idempotencyKeys) async {
    if (idempotencyKeys.isEmpty) return;
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    try {
      for (final key in idempotencyKeys) {
        final storageKey = _storageKey(ownerId, key);
        final existing = await store.getObject(storageKey);
        if (existing == null) continue;
        final row = Map<Object?, Object?>.from(existing as Map);
        if (row['owner_id'] != ownerId) continue;
        row['status'] = 'conflict';
        row['last_error'] = 'revision_conflict';
        await store.put({...row, 'storage_key': storageKey});
      }
      await transaction.completed;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<List<QrSyncMutation>> allForOwner(String ownerId) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadOnly);
    try {
      final rows = await transaction.objectStore(_storeName).getAll();
      await transaction.completed;
      return rows
          .map((value) => QrSyncMutation.fromStorageMap(Map<Object?, Object?>.from(value as Map)))
          .where((mutation) => mutation.ownerId == ownerId)
          .toList(growable: false);
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<int> pendingCount(String ownerId) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadOnly);
    try {
      final rows = await transaction.objectStore(_storeName).getAll();
      await transaction.completed;
      return rows.where((value) {
        final row = Map<Object?, Object?>.from(value as Map);
        return row['owner_id'] == ownerId && row['status'] == 'pending';
      }).length;
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  Future<void> close() async {
    final opening = _database;
    _database = null;
    if (opening != null) (await opening).close();
  }

  Future<void> _finishAfterFailure(Transaction transaction) async {
    try {
      await transaction.completed;
    } on Object {
      // Keep the original operation error.
    }
  }

  String _storageKey(String ownerId, String idempotencyKey) =>
      '$ownerId::$idempotencyKey';

  bool _sameMutation(QrSyncMutation a, QrSyncMutation b) =>
      a.ownerId == b.ownerId &&
      a.recordId == b.recordId &&
      a.type == b.type &&
      a.baseRevision == b.baseRevision &&
      jsonEncode(a.toStorageMap()['payload_json']) ==
          jsonEncode(b.toStorageMap()['payload_json']);
}
