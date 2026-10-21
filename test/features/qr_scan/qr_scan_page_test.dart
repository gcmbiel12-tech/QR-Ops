import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/features/qr_scan/qr_scan_page.dart';

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

Widget _testApp({QrScanUrlLauncher? urlLauncher}) => MaterialApp(
  home: Scaffold(
    body: QrScanPage(
      isActive: true,
      urlLauncher: urlLauncher,
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
