import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/features/qr_scan/qr_scan_page.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/domain/qr_record_repository.dart';

void main() {
  testWidgets('opens a valid HTTP URL and still copies its exact content', (
    tester,
  ) async {
    _setLargeTestViewport(tester);
    final launched = <Uri>[];
    final copied = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add(
          (call.arguments as Map<Object?, Object?>)['text']! as String,
        );
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      _testApp(
        urlLauncher: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scan-url')));
    await tester.pumpAndSettle();

    final resultFinder = find.byKey(const ValueKey('qr-scan-result-value'));
    const value = 'https://example.com/rota?q=setor%201#inicio';
    expect(tester.widget<SelectableText>(resultFinder).data, value);
    await tester.tap(resultFinder);
    await tester.pumpAndSettle();
    expect(find.text('Confirmar ação externa'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(launched, [Uri.parse(value)]);

    await tester.tap(find.byKey(const ValueKey('qr-scan-copy')));
    await tester.pumpAndSettle();
    expect(copied, [value]);
  });

  testWidgets('does not make ordinary text actionable as a link', (
    tester,
  ) async {
    _setLargeTestViewport(tester);
    final launched = <Uri>[];
    await tester.pumpWidget(
      _testApp(
        urlLauncher: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scan-once')));
    await tester.pumpAndSettle();

    final result = tester.widget<SelectableText>(
      find.byKey(const ValueKey('qr-scan-result-value')),
    );
    expect(result.data, 'ID-2');
    expect(result.onTap, isNull);
    await tester.tap(find.byKey(const ValueKey('qr-scan-result-value')));
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
  });

  testWidgets('does not add a scheme to a host without one', (tester) async {
    _setLargeTestViewport(tester);
    await tester.pumpWidget(_testApp(urlLauncher: (_) async => true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scan-domain')));
    await tester.pumpAndSettle();

    final result = tester.widget<SelectableText>(
      find.byKey(const ValueKey('qr-scan-result-value')),
    );
    expect(result.data, 'exemplo.com/rota');
    expect(result.onTap, isNull);
  });

  testWidgets('shows an error when the browser cannot open the URL', (
    tester,
  ) async {
    _setLargeTestViewport(tester);
    await tester.pumpWidget(_testApp(urlLauncher: (_) async => false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scan-url')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('qr-scan-result-value')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível abrir este link no navegador.'),
      findsOneWidget,
    );
  });

  testWidgets('shows and copies a numeric barcode result and can scan again', (
    tester,
  ) async {
    _setLargeTestViewport(tester);
    final copiedValues = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedValues.add(
          (call.arguments as Map<Object?, Object?>)['text']! as String,
        );
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fake-scan-twice')));
    await tester.pumpAndSettle();

    expect(find.text('Formato: EAN-13'), findsOneWidget);
    expect(find.text('Tipo identificado: Texto'), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-scan-context-action')), findsNothing);
    expect(find.byKey(const ValueKey('qr-scan-result-value')), findsOneWidget);
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('qr-scan-result-value')),
          )
          .data,
      '5901234123457',
    );
    expect(find.byKey(const ValueKey('qr-scan-copy')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('qr-scan-copy')));
    await tester.tap(find.byKey(const ValueKey('qr-scan-copy')));
    await tester.pumpAndSettle();
    expect(find.text('Conteúdo copiado.'), findsOneWidget);
    expect(copiedValues, ['5901234123457']);

    await tester.tap(find.byKey(const ValueKey('qr-scan-again')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scan-once')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('qr-scan-result-value')),
          )
          .data,
      'ID-2',
    );
  });

  testWidgets('saves a scanned result only when requested', (tester) async {
    _setLargeTestViewport(tester);
    final repository = _MemoryQrRecordRepository();
    var refreshes = 0;
    await tester.pumpWidget(
      _testApp(repository: repository, onRecordRead: () => refreshes++),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scan-once')));
    await tester.pumpAndSettle();

    expect(repository.records, isEmpty);
    expect(find.byKey(const ValueKey('qr-scan-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('qr-scan-save')));
    await tester.pumpAndSettle();

    expect(repository.records, hasLength(1));
    expect(repository.records.single.content, 'ID-2');
    expect(repository.records.single.operation, QrRecordOperation.read);
    expect(refreshes, 1);
    expect(find.text('Salvo no histórico'), findsOneWidget);
    expect(find.text('Leitura salva no histórico.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('qr-scan-save')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('ignores detections while the reader area is inactive', (
    tester,
  ) async {
    _setLargeTestViewport(tester);
    await tester.pumpWidget(_testApp(isActive: false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fake-scan-once')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qr-scan-result')), findsNothing);

    await tester.pumpWidget(_testApp(isActive: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scan-once')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qr-scan-result')), findsOneWidget);
  });

  testWidgets('shows a recoverable camera error and offers retry', (
    tester,
  ) async {
    _setLargeTestViewport(tester);
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fake-camera-error')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qr-scan-error')), findsOneWidget);
    expect(find.textContaining('Permita o acesso à câmera'), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-scan-retry')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('qr-scan-retry')));
    await tester.tap(find.byKey(const ValueKey('qr-scan-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qr-scan-error')), findsNothing);
    expect(find.byKey(const ValueKey('fake-scan-twice')), findsOneWidget);
  });
}

void _setLargeTestViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _testApp({
  QrScanUrlLauncher? urlLauncher,
  bool isActive = true,
  QrRecordRepository? repository,
  VoidCallback? onRecordRead,
}) => MaterialApp(
  home: Scaffold(
    body: QrScanPage(
      isActive: isActive,
      urlLauncher: urlLauncher,
      repository: repository,
      onRecordRead: onRecordRead,
      previewBuilder: (context, onResult, onError) => ColoredBox(
        color: Colors.black12,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              key: const ValueKey('fake-scan-twice'),
              onPressed: () {
                const first = QrScanResult(
                  value: '5901234123457',
                  format: 'EAN-13',
                );
                onResult(first);
                onResult(
                  const QrScanResult(value: 'duplicate', format: 'EAN-13'),
                );
              },
              child: const Text('Emitir duas detecções'),
            ),
            TextButton(
              key: const ValueKey('fake-scan-url'),
              onPressed: () => onResult(
                const QrScanResult(
                  value: 'https://example.com/rota?q=setor%201#inicio',
                  format: 'QR Code',
                ),
              ),
              child: const Text('Emitir URL'),
            ),
            TextButton(
              key: const ValueKey('fake-scan-once'),
              onPressed: () => onResult(
                const QrScanResult(value: 'ID-2', format: 'Code 128'),
              ),
              child: const Text('Emitir detecção'),
            ),
            TextButton(
              key: const ValueKey('fake-scan-domain'),
              onPressed: () => onResult(
                const QrScanResult(
                  value: 'exemplo.com/rota',
                  format: 'QR Code',
                ),
              ),
              child: const Text('Emitir domínio'),
            ),
            TextButton(
              key: const ValueKey('fake-camera-error'),
              onPressed: () => onError(
                'O acesso à câmera foi negado. Permita o acesso à câmera '
                'nas configurações e tente novamente.',
              ),
              child: const Text('Emitir erro'),
            ),
          ],
        ),
      ),
    ),
  ),
);

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
  Future<QrRecord?> findById(String id) async =>
      records.where((record) => record.id == id).firstOrNull;

  @override
  Future<bool> deleteById(String id) async => false;

  @override
  Future<bool> updateById(QrRecord record) async => false;

  @override
  Future<int> pruneReadHistoryBefore(DateTime cutoffUtc) async => 0;

  @override
  Future<int> deleteAllReadHistory() async => 0;
}
