import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/app/qr_ops_app.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/domain/qr_record_repository.dart';

void main() {
  testWidgets('fits a phone browser and creates a local QR record', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _MemoryQrRecordRepository();

    await tester.pumpWidget(QrOpsApp(repository: repository));
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-criar')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('qr-content-field')),
      'QR Ops no navegador',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qr-preview')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('qr-save-button')));
    await tester.pumpAndSettle();
    expect(repository.records, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('nav-organizar')));
    await tester.pumpAndSettle();
    expect(find.text('QR Ops no navegador'), findsOneWidget);
  });

  testWidgets('uses desktop navigation in a wide browser viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(QrOpsApp(repository: _MemoryQrRecordRepository()));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}

class _MemoryQrRecordRepository implements QrRecordRepository {
  final List<QrRecord> records = [];

  @override
  Future<QrRecord> insert(QrRecord record) async {
    records.add(record);
    return record;
  }

  @override
  Future<List<QrRecord>> listLatest({int limit = 100}) async =>
      records.reversed.take(limit).toList(growable: false);

  @override
  Future<QrRecord?> findById(String id) async {
    for (final record in records) {
      if (record.id == id) return record;
    }
    return null;
  }

  @override
  Future<bool> deleteById(String id) async {
    final oldLength = records.length;
    records.removeWhere((record) => record.id == id);
    return records.length < oldLength;
  }
}
