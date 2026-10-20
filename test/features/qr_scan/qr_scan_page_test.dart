import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/features/qr_scan/qr_scan_page.dart';

void main() {
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
    expect(
      find.byKey(const ValueKey('qr-scan-result-value')),
      findsOneWidget,
    );
    expect(
      tester.widget<SelectableText>(
        find.byKey(const ValueKey('qr-scan-result-value')),
      ).data,
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
      tester.widget<SelectableText>(
        find.byKey(const ValueKey('qr-scan-result-value')),
      ).data,
      'ID-2',
    );
  });

  testWidgets('shows a recoverable camera error and offers retry', (tester) async {
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

Widget _testApp() => MaterialApp(
  home: Scaffold(
    body: QrScanPage(
      isActive: true,
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
              key: const ValueKey('fake-scan-once'),
              onPressed: () => onResult(
                const QrScanResult(value: 'ID-2', format: 'Code 128'),
              ),
              child: const Text('Emitir detecção'),
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
