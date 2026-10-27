import 'dart:convert';

import 'package:archive/archive.dart';
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
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files, hasLength(3));
      final names = archive.files.map((file) => file.name).toSet();
      expect(names, hasLength(3));
      expect(names.every((name) => name.endsWith('.png')), isTrue);
      for (final file in archive.files) {
        final png = file.content as List<int>;
        expect(png.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
      }
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

  test('preserves Portuguese accents and identifies repeated label items', () {
    final text = latin1.decode(
      exporter.buildPdf(['AÇÃO-001', 'AÇÃO-001'], service, size: 'Grande'),
    );
    expect(text, contains(r'(A\307\303O-001) Tj'));
    expect(text, contains('(Item 1 de 2) Tj'));
    expect(text, contains('(Item 2 de 2) Tj'));
    expect(text, contains('/MediaBox [0 0 595.0 842.0]'));
  });

  test('exports 500 label codes in 28 pages and labels every item', () {
    final contents = List<String>.generate(
      500,
      (index) => 'QR-AUDIT-${(index + 1).toString().padLeft(4, '0')}',
    );
    final text = latin1.decode(
      exporter.buildPdf(contents, service, size: 'Grande'),
    );
    expect(text, contains('/Count 28'));
    expect(RegExp(r'\(Item \d+ de 500\) Tj').allMatches(text), hasLength(500));
    expect(text, contains('/MediaBox [0 0 595.0 842.0]'));
  });

  test('maps all offered print sizes to distinct PDF dimensions', () {
    expect(exporter.printSizeFor('Pequeno'), 68);
    expect(exporter.printSizeFor('Médio'), 88);
    expect(exporter.printSizeFor('Grande'), 108);
    final small = exporter.buildPdf(['QR-SIZE-TEST'], service, size: 'Pequeno');
    final medium = exporter.buildPdf(['QR-SIZE-TEST'], service, size: 'Médio');
    final large = exporter.buildPdf(['QR-SIZE-TEST'], service, size: 'Grande');
    expect(small, isNot(equals(medium)));
    expect(medium, isNot(equals(large)));
  });
}

class _UnusedRepository implements QrRecordRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
