import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/data/app_database.dart';
import 'package:qr_ops/data/sqlite_qr_record_repository.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/features/qr_create/qr_batch_create_page.dart';
import 'package:qr_ops/features/qr_create/qr_creation_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late SqliteQrRecordRepository repository;
  var createdCallbackCount = 0;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    createdCallbackCount = 0;
    database = await AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    ).open();
    repository = SqliteQrRecordRepository(database);
  });
  tearDown(() => database.close());

  testWidgets('previews a batch and only saves after explicit confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrBatchCreatePage(
          service: QrCreationService(repository),
          onRecordsCreated: () => createdCallbackCount++,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('qr-batch-input')),
      '1001-1003;ABC-001',
    );
    await tester.tap(find.byKey(const ValueKey('qr-batch-preview')));
    await tester.pumpAndSettle();

    expect(find.text('4 itens • 4 selecionados'), findsOneWidget);
    expect(await tester.runAsync(repository.listLatest), isEmpty);

    await tester.tap(find.byKey(const ValueKey('qr-batch-save-selected')));
    await tester.pumpAndSettle();
    expect(find.text('Salvar QR Codes selecionados?'), findsOneWidget);
    expect(await tester.runAsync(repository.listLatest), isEmpty);

    await tester.tap(find.text('Salvar selecionados').last);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Resultado do salvamento'), findsOneWidget);
    await tester.tap(find.text('Concluir'));
    await tester.pumpAndSettle();

    final saved = (await tester.runAsync(repository.listLatest))!;
    expect(saved.map((record) => record.content).toSet(), {
      '1001',
      '1002',
      '1003',
      'ABC-001',
    });
    expect(
      saved.every((record) => record.operation == QrRecordOperation.create),
      isTrue,
    );
    expect(createdCallbackCount, 1);
  });
}
