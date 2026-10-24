import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/domain/qr_record_repository.dart';
import 'package:qr_ops/features/qr_history/qr_history_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('copies the content directly from a history item', (
    tester,
  ) async {
    const content = 'Texto completo para copiar do histórico';
    final repository = _MemoryQrRecordRepository([
      QrRecord.read(
        content: content,
        symbology: 'qr',
        createdAt: DateTime.utc(2026, 10, 24),
      ),
    ]);
    final copiedData = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedData.add(
              (call.arguments as Map<Object?, Object?>)['text'] as String,
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QrHistoryPage(
            repository: repository,
            refreshToken: 0,
            isActive: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('qr-history-copy-${repository.records.single.id}')),
    );
    await tester.pumpAndSettle();

    expect(copiedData, [content]);
    expect(
      find.text('Conteúdo copiado para a área de transferência.'),
      findsOneWidget,
    );
  });
}

class _MemoryQrRecordRepository implements QrRecordRepository {
  _MemoryQrRecordRepository(this.records);

  final List<QrRecord> records;

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
  Future<int> pruneReadHistoryBefore(DateTime cutoffUtc) async => 0;

  @override
  Future<int> deleteAllReadHistory() async => 0;

  @override
  Future<bool> deleteById(String id) async => false;

  @override
  Future<bool> updateById(QrRecord record) async => false;
}
