import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/qr_record.dart';
import '../domain/qr_sync_contract.dart';

class SupabaseQrSyncTransport implements QrSyncPullTransport {
  const SupabaseQrSyncTransport(this.client);

  final SupabaseClient client;

  @override
  Future<List<QrSyncApplyResult>> applyBatch(
    String ownerId,
    List<QrSyncMutation> mutations,
  ) async {
    _requireOwner(ownerId);
    if (mutations.isEmpty) return const [];
    final response = await client.rpc(
      'apply_qr_sync_batch',
      params: {
        'p_mutations': mutations.map(_mutationToJson).toList(growable: false),
      },
    );
    if (response is! List) {
      throw const FormatException(
        'Resposta inválida do protocolo de sincronização.',
      );
    }
    return response
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Resultado de sincronização inválido.');
          }
          final row = Map<String, dynamic>.from(item);
          final key = row['idempotency_key'];
          final status = switch (row['status']) {
            'applied' => QrSyncApplyStatus.applied,
            'already_applied' => QrSyncApplyStatus.alreadyApplied,
            'conflict' => QrSyncApplyStatus.conflict,
            'retryable_failure' => QrSyncApplyStatus.retryableFailure,
            final value => throw FormatException(
              'Estado remoto desconhecido: $value',
            ),
          };
          final revision = row['revision'];
          if (key is! String) {
            throw const FormatException('Resposta sem chave idempotente.');
          }
          return QrSyncApplyResult(
            key,
            status,
            revision: revision is num ? revision.toInt() : null,
            message: row['message'] as String?,
            recordId: row['record_id'] as String?,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<QrSyncSnapshot> fetchSnapshot(String ownerId) async {
    _requireOwner(ownerId);
    final rows = await client
        .from('qr_records')
        .select(
          'id, operation_type, symbology, content_type, content, name, description, created_at, revision',
        )
        .eq('author_id', ownerId)
        .order('updated_at', ascending: true)
        .limit(1000);
    final records = rows
        .map((row) => _recordFromRow(row))
        .toList(growable: false);
    final tombstoneRows = await client
        .from('qr_record_tombstones')
        .select('record_id, revision')
        .eq('owner_id', ownerId)
        .limit(1000);
    final tombstones = <String, int>{};
    for (final row in tombstoneRows) {
      final id = row['record_id'];
      final revision = row['revision'];
      if (id is String && revision is num) tombstones[id] = revision.toInt();
    }
    return QrSyncSnapshot(records: records, tombstones: tombstones);
  }

  void _requireOwner(String ownerId) {
    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) {
      throw StateError('A sessão autenticada expirou antes da sincronização.');
    }
    if (sessionUser.id != ownerId) {
      throw StateError('A fila pertence a outra conta; envio cancelado.');
    }
  }

  Map<String, Object?> _mutationToJson(QrSyncMutation mutation) {
    final record = mutation.record;
    return {
      'idempotency_key': mutation.idempotencyKey,
      'record_id': mutation.recordId,
      'type': switch (mutation.type) {
        QrSyncMutationType.upsert => 'upsert',
        QrSyncMutationType.delete => 'delete',
      },
      'base_revision': mutation.baseRevision,
      if (record != null)
        'record': {
          'id': record.id,
          'operation_type': switch (record.operation) {
            QrRecordOperation.create => 'create',
            QrRecordOperation.read => 'read',
            QrRecordOperation.ocr => throw StateError(
              'Registros OCR são locais e não podem ser sincronizados.',
            ),
          },
          'symbology': record.symbology,
          'content_type': record.contentType,
          'content': record.content,
          'name': record.name,
          'description': record.description,
          'created_at': record.createdAt.toUtc().toIso8601String(),
        },
    };
  }

  QrRecord _recordFromRow(Map<String, dynamic> row) {
    final operation = switch (row['operation_type']) {
      'create' => QrRecordOperation.create,
      'read' => QrRecordOperation.read,
      final value => throw FormatException(
        'Operação remota desconhecida: $value',
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
