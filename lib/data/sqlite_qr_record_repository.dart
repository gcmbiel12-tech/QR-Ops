import 'package:sqflite/sqflite.dart';

import '../domain/qr_record.dart';
import '../domain/qr_record_repository.dart';

class SqliteQrRecordRepository implements QrRecordRepository {
  const SqliteQrRecordRepository(this._database);

  final Database _database;

  @override
  Future<QrRecord> insert(QrRecord record) async {
    if (record.id.isEmpty) {
      throw ArgumentError.value(record.id, 'record.id');
    }
    if (record.content.trim().isEmpty) {
      throw ArgumentError.value(record.content, 'record.content');
    }

    await _database.insert(
      'qr_records',
      _toRow(record),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
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
    final deleted = await _database.delete(
      'qr_records',
      where: 'id = ?',
      whereArgs: [id],
    );
    return deleted > 0;
  }

  Map<String, Object?> _toRow(QrRecord record) => {
    'id': record.id,
    'operation_type': _operationToStorage(record.operation),
    'symbology': record.symbology,
    'content_type': record.contentType,
    'content': record.content,
    'created_at_ms': record.createdAt.toUtc().millisecondsSinceEpoch,
  };

  QrRecord _fromRow(Map<String, Object?> row) {
    final operation = switch (row['operation_type']) {
      'create' => QrRecordOperation.create,
      'read' => QrRecordOperation.read,
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
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at_ms']! as int,
        isUtc: true,
      ),
    );
  }

  String _operationToStorage(QrRecordOperation operation) =>
      switch (operation) {
        QrRecordOperation.create => 'create',
        QrRecordOperation.read => 'read',
      };
}
