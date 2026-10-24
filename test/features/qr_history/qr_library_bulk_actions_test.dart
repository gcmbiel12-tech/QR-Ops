import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/data/app_database.dart';
import 'package:qr_ops/data/sqlite_qr_record_repository.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/features/qr_history/qr_library_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late SqliteQrRecordRepository repository;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = await AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    ).open();
    repository = SqliteQrRecordRepository(database);
    await repository.insert(
      QrRecord.created(content: 'item-A', contentType: 'text'),
    );
    await repository.insert(
      QrRecord.created(content: 'item-B', contentType: 'text'),
    );
  });
  tearDown(() => database.close());

  testWidgets('selects filtered library items and confirms batch deletion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QrLibraryPage(repository: repository, refreshToken: 0),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('qr-library-select-filtered')));
    await tester.pumpAndSettle();
    expect(find.text('2 selecionados de 2'), findsOneWidget);

    await tester.tap(find.text('Excluir selecionados'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir QR Codes selecionados?'), findsOneWidget);
    expect(
      find.text(
        '2 QR Codes serão removidos da biblioteca local. O histórico de leituras será preservado.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Excluir selecionados').last);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(await tester.runAsync(repository.listLatest), isEmpty);
  });
}
