import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/app/qr_ops_bootstrap.dart';
import 'package:qr_ops/domain/qr_record_repository.dart';

void main() {
  testWidgets('shows a safe error and retries database initialization', (
    tester,
  ) async {
    var attempts = 0;

    Future<QrRecordRepository> failToOpenDatabase() async {
      attempts++;
      throw StateError('internal diagnostic that must not be shown');
    }

    await tester.pumpWidget(QrOpsBootstrap(openRepository: failToOpenDatabase));
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível preparar o armazenamento local.'),
      findsOneWidget,
    );
    expect(find.textContaining('internal diagnostic'), findsNothing);
    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(
      find.text('Não foi possível preparar o armazenamento local.'),
      findsOneWidget,
    );
  });
}
