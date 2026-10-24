import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_ops/data/supabase_qr_record_repository.dart';
import 'package:qr_ops/domain/qr_record.dart';

void main() {
  late SupabaseClient client;
  late SupabaseQrRecordRepository repository;

  setUp(() {
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
    );
    repository = SupabaseQrRecordRepository(client);
  });

  tearDown(() => client.dispose());

  test(
    'maps remote row to stable domain model and normalizes UTC timestamp',
    () {
      final record = repository.fromRow({
        'id': '5d4a0b8c-59cc-47c0-a49d-5b54e61db9b0',
        'operation_type': 'create',
        'symbology': 'qr',
        'content_type': 'pdf',
        'content': 'https://example.com/document.pdf?download=1',
        'name': 'Manual',
        'description': 'Documento de referência',
        'created_at': '2026-10-23T15:30:00-03:00',
      });

      expect(record.id, '5d4a0b8c-59cc-47c0-a49d-5b54e61db9b0');
      expect(record.operation, QrRecordOperation.create);
      expect(record.contentType, 'pdf');
      expect(record.content, 'https://example.com/document.pdf?download=1');
      expect(record.name, 'Manual');
      expect(record.description, 'Documento de referência');
      expect(record.createdAt.isUtc, isTrue);
      expect(record.createdAt, DateTime.utc(2026, 10, 23, 18, 30));
    },
  );

  test('maps read operation and tolerates pre-metadata rows', () {
    final record = repository.fromRow({
      'id': 'legacy-id',
      'operation_type': 'read',
      'symbology': 'qr',
      'content_type': 'text',
      'content': 'texto lido',
      'created_at': '2026-10-23T18:30:00Z',
    });

    expect(record.operation, QrRecordOperation.read);
    expect(record.name, isEmpty);
    expect(record.description, isEmpty);
  });

  test('rejects unknown operation instead of silently mapping to read', () {
    expect(
      () => repository.fromRow({
        'id': 'bad',
        'operation_type': 'unexpected',
        'symbology': 'qr',
        'content_type': 'text',
        'content': 'payload',
        'created_at': '2026-10-23T18:30:00Z',
      }),
      throwsFormatException,
    );
  });

  test('refuses remote reads without an authenticated session', () async {
    await expectLater(repository.listLatest(), throwsStateError);
    await expectLater(repository.findById('any-id'), throwsStateError);
    await expectLater(repository.deleteById('any-id'), throwsStateError);
    await expectLater(
      repository.pruneReadHistoryBefore(DateTime.utc(2026)),
      throwsStateError,
    );
  });
}
