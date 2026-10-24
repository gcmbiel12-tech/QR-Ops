import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/domain/qr_record_repository.dart';
import 'package:qr_ops/features/qr_scan/qr_ocr_page.dart';

void main() {
  late _MemoryRepository repository;
  var recognitions = 0;
  var savedCallbacks = 0;

  setUp(() {
    repository = _MemoryRepository();
    recognitions = 0;
    savedCallbacks = 0;
  });

  testWidgets(
    'runs OCR only after the explicit Scanear action and saves reviewed text locally',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final imageBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a3sAAAAASUVORK5CYII=',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrOcrPage(
              repository: repository,
              initialImageBytes: imageBytes,
              recognizeImage: (bytes) async {
                recognitions++;
                return 'Texto de teste';
              },
              onRecordSaved: () => savedCallbacks++,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(recognitions, 0);
      expect(repository.records, isEmpty);
      await tester.tap(find.byKey(const ValueKey('ocr-scan-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(recognitions, 1);
      expect(
        find.text(
          'Revise e corrija o texto reconhecido antes de salvar ou exportar.',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('ocr-name')),
        'Nota de teste',
      );
      await tester.tap(find.byKey(const ValueKey('ocr-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(repository.records, hasLength(1));
      expect(repository.records.single.operation, QrRecordOperation.ocr);
      expect(repository.records.single.name, 'Nota de teste');
      expect(repository.records.single.content, 'Texto de teste');
      expect(savedCallbacks, 1);
    },
  );
}

class _MemoryRepository extends Fake implements QrRecordRepository {
  final List<QrRecord> records = [];

  @override
  Future<QrRecord> insert(QrRecord record) async {
    records.add(record);
    return record;
  }

  @override
  Future<bool> updateById(QrRecord record) async {
    final index = records.indexWhere((item) => item.id == record.id);
    if (index < 0) return false;
    records[index] = record;
    return true;
  }

  @override
  Future<List<QrRecord>> listLatest({int limit = 100}) async =>
      records.take(limit).toList();
}
