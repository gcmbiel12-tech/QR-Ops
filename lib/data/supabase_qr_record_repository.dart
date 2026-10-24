import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/qr_record.dart';
import '../domain/qr_record_repository.dart';

class SupabaseQrRecordRepository implements QrRecordRepository {
  SupabaseQrRecordRepository(this.client);
  final SupabaseClient client;
  static const table = 'qr_records';

  void requireSession() {
    if (client.auth.currentUser == null) {
      throw StateError(
        'Autenticacao necessaria para o historico compartilhado.',
      );
    }
  }

  @override
  Future<QrRecord> insert(QrRecord record) async {
    requireSession();
    await client.from(table).insert({
      'id': record.id,
      'author_id': client.auth.currentUser!.id,
      'operation_type': record.operation == QrRecordOperation.create
          ? 'create'
          : 'read',
      'symbology': record.symbology,
      'content_type': record.contentType,
      'content': record.content,
      'name': record.name,
      'description': record.description,
      'created_at': record.createdAt.toUtc().toIso8601String(),
    });
    return record;
  }

  @override
  Future<List<QrRecord>> listLatest({int limit = 100}) async {
    requireSession();
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final rows = await client
        .from(table)
        .select(
          'id, operation_type, symbology, content_type, content, name, description, created_at, revision',
        )
        .eq('author_id', client.auth.currentUser!.id)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return rows.map((row) => fromRow(row)).toList(growable: false);
  }

  @override
  Future<QrRecord?> findById(String id) async {
    requireSession();
    final rows = await client
        .from(table)
        .select(
          'id, operation_type, symbology, content_type, content, name, description, created_at, revision',
        )
        .eq('author_id', client.auth.currentUser!.id)
        .eq('id', id)
        .limit(1);
    return rows.isEmpty ? null : fromRow(rows.first);
  }

  @override
  Future<bool> deleteById(String id) async {
    requireSession();
    final rows = await client
        .from(table)
        .delete()
        .eq('author_id', client.auth.currentUser!.id)
        .eq('id', id)
        .select('id');
    return rows.isNotEmpty;
  }

  @override
  Future<bool> updateById(QrRecord record) async {
    requireSession();
    final rows = await client
        .from(table)
        .update({
          'operation_type': record.operation == QrRecordOperation.create
              ? 'create'
              : 'read',
          'symbology': record.symbology,
          'content_type': record.contentType,
          'content': record.content,
          'name': record.name,
          'description': record.description,
        })
        .eq('author_id', client.auth.currentUser!.id)
        .eq('id', record.id)
        .select('id');
    return rows.isNotEmpty;
  }

  @override
  Future<int> pruneReadHistoryBefore(DateTime cutoffUtc) async {
    requireSession();
    final rows = await client
        .from(table)
        .delete()
        .eq('operation_type', 'read')
        .lt('created_at', cutoffUtc.toUtc().toIso8601String())
        .eq('author_id', client.auth.currentUser!.id)
        .select('id');
    return rows.length;
  }

  @override
  Future<int> deleteAllReadHistory() async {
    requireSession();
    final rows = await client
        .from(table)
        .delete()
        .eq('operation_type', 'read')
        .eq('author_id', client.auth.currentUser!.id)
        .select('id');
    return rows.length;
  }

  QrRecord fromRow(Map<String, dynamic> row) {
    final operation = switch (row['operation_type']) {
      'create' => QrRecordOperation.create,
      'read' => QrRecordOperation.read,
      final value => throw FormatException(
        'Operação desconhecida no registro Supabase: $value',
      ),
    };
    return QrRecord(
      id: row['id'] as String,
      operation: operation,
      symbology: row['symbology'] as String,
      contentType: row['content_type'] as String,
      content: row['content'] as String,
      name: row['name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      revision: (row['revision'] as num?)?.toInt() ?? 1,
    );
  }
}
