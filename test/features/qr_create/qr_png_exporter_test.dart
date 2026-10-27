import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qr_ops/domain/qr_record_repository.dart';
import 'package:qr_ops/features/qr_create/qr_creation_service.dart';
import 'package:qr_ops/features/qr_create/qr_png_exporter.dart';

void main() {
  const exporter = QrPngExporter();
  final service = QrCreationService(_UnusedRepository());

  test('exports PNGs at each supported resolution', () async {
    final matrix = service.encode('QR-PNG-AUDIT-001');
    for (final dimension in [256, 512, 1024, 2048]) {
      final bytes = await exporter.export(matrix, dimension: dimension);
      expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
      final header = ByteData.sublistView(bytes, 16, 24);
      expect(header.getUint32(0), dimension);
      expect(header.getUint32(4), dimension);
    }
  });

  test('rejects unsupported dimensions and insufficient contrast', () async {
    final matrix = service.encode('QR-PNG-AUDIT-002');
    await expectLater(
      exporter.export(matrix, dimension: 300),
      throwsArgumentError,
    );
    await expectLater(
      exporter.export(
        matrix,
        dimension: 256,
        foreground: const Color(0xFFAAAAAA),
        background: const Color(0xFFFFFFFF),
      ),
      throwsArgumentError,
    );
  });

  test('keeps the requested square output dimensions', () async {
    final matrix = service.encode('QR-PNG-AUDIT-003');
    final bytes = await exporter.export(matrix, dimension: 512);
    final header = ByteData.sublistView(bytes, 16, 24);
    expect(header.getUint32(0), 512);
    expect(header.getUint32(4), 512);
  });
}

class _UnusedRepository implements QrRecordRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
