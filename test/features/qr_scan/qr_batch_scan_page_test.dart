import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/data/app_database.dart';
import 'package:qr_ops/data/sqlite_qr_record_repository.dart';
import 'package:qr_ops/features/qr_scan/qr_batch_scan_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late SqliteQrRecordRepository repository;
  var savedCallbackCount = 0;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    savedCallbackCount = 0;
    database = await AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    ).open();
    repository = SqliteQrRecordRepository(database);
  });
  tearDown(() => database.close());

  testWidgets('does not start reading or save records when the screen opens', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrBatchScanPage(
          repository: repository,
          onRecordsSaved: () => savedCallbackCount++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Iniciar leitura'), findsOneWidget);
    expect(find.text('0 códigos capturados'), findsOneWidget);
    expect(find.textContaining('Leitura ativa.'), findsNothing);
    expect(await tester.runAsync(repository.listLatest), isEmpty);
    expect(savedCallbackCount, 0);
  });
}
