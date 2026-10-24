import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/domain/qr_record_repository.dart';
import 'package:qr_ops/features/qr_create/qr_batch_export_service.dart';
import 'package:qr_ops/features/qr_create/qr_creation_service.dart';

void main() {
  const exporter = QrBatchExportService();
  final service = QrCreationService(_UnusedRepository());

  test(
    'exports a ZIP containing unique PNG names for duplicate contents',
    () async {
      final bytes = await exporter.buildZip(
        ['ABC-001', 'ABC-001', '1002'],
        service,
        size: 'Pequeno',
      );
      expect(bytes.length, greaterThan(30));
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4b);
    },
  );

  test('creates a valid PDF structure with one page per expected group', () {
    final bytes = exporter.buildPdf(
      ['A-001', 'B-002', 'C-003'],
      service,
      labelSheet: true,
    );
    final text = latin1.decode(bytes);
    expect(text.startsWith('%PDF-1.4'), isTrue);
    expect(text, contains('/Type /Catalog'));
    expect(text, contains('/Type /Pages'));
    expect(text, contains('/Count 1'));
    expect(text, contains('startxref'));
    expect(text.trimRight().endsWith('%%EOF'), isTrue);
  });

  test('supports report pagination and rejects empty exports', () {
    final bytes = exporter.buildPdf(
      ['A', 'B', 'C'],
      service,
      labelSheet: false,
    );
    expect(latin1.decode(bytes), contains('/Count 2'));
    expect(() => exporter.buildPdf([], service), throwsArgumentError);
  });
}

class _UnusedRepository implements QrRecordRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
