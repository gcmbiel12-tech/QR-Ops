import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/features/qr_scan/qr_scan_page.dart';

void main() {
  testWidgets('shows and copies a numeric barcode result and can scan again', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fake-scan-twice')));
    await tester.pumpAndSettle();

    expect(find.text('Formato: EAN-13'), findsOneWidget);
    expect(find.text('5901234123457'), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-scan-copy')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('qr-scan-copy')));
    await tester.pumpAndSettle();
    expect(find.text('Conteúdo copiado.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('qr-scan-again')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scan-once')));
    await tester.pumpAndSettle();
    expect(find.text('ID-2'), findsOneWidget);
  });

  testWidgets('shows a recoverable camera error and offers retry', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fake-camera-error')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qr-scan-error')), findsOneWidget);
    expect(find.textContaining('Permita o acesso à câmera'), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-scan-retry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('qr-scan-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qr-scan-error')), findsNothing);
    expect(find.byKey(const ValueKey('fake-scan-twice')), findsOneWidget);
  });
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
