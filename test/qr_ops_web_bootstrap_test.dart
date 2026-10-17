import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/app/qr_ops_bootstrap.dart';

void main() {
  testWidgets('starts the QR Ops application with browser storage', (
    tester,
  ) async {
    await tester.pumpWidget(const QrOpsBootstrap());
    await tester.pumpAndSettle();

    expect(
      find.text('Sua base para operações com códigos QR.'),
      findsOneWidget,
    );
  }, skip: !kIsWeb);
}
