import 'package:idb_shim/idb.dart';

import '../domain/qr_record.dart';
import '../domain/qr_record_repository.dart';

class IndexedDbQrRecordRepository implements QrRecordRepository {
  IndexedDbQrRecordRepository({
    required this.factory,
    this.databaseName = defaultDatabaseName,
  });

  static const defaultDatabaseName = 'qr_ops_history';
  static const _databaseVersion = 1;
  static const _storeName = 'qr_records';

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
        if (event.oldVersion < _databaseVersion) {
          event.database.createObjectStore(_storeName, keyPath: 'id');
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

    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    try {
      await transaction.objectStore(_storeName).add(_toRow(record));
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
      final rows = await transaction.objectStore(_storeName).getAll();
      await transaction.completed;

      final records = rows.map(_fromRow).toList(growable: false)
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
      final row = await transaction.objectStore(_storeName).getObject(id);
      await transaction.completed;
      return row == null ? null : _fromRow(row);
    } on Object {
      await _finishAfterFailure(transaction);
      rethrow;
    }
  }

  @override
  Future<bool> deleteById(String id) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    try {
      final existing = await store.getObject(id);
      if (existing != null) await store.delete(id);
      await transaction.completed;
      return existing != null;
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
      // Preserve the operation error while observing the transaction failure.
    }
  }

  Map<String, Object> _toRow(QrRecord record) => {
    'id': record.id,
    'operation_type': switch (record.operation) {
      QrRecordOperation.create => 'create',
      QrRecordOperation.read => 'read',
    },
    'symbology': record.symbology,
    'content_type': record.contentType,
    'content': record.content,
    'created_at_ms': record.createdAt.toUtc().millisecondsSinceEpoch,
  };

  QrRecord _fromRow(Object value) {
    if (value is! Map) {
      throw const FormatException('Registro inválido no histórico IndexedDB.');
    }
    final row = Map<Object?, Object?>.from(value);
    final operation = switch (row['operation_type']) {
      'create' => QrRecordOperation.create,
      'read' => QrRecordOperation.read,
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
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        timestamp.toInt(),
        isUtc: true,
      ),
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
