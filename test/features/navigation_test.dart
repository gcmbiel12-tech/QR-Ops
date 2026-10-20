import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/app/qr_ops_app.dart';
import 'package:qr_ops/data/app_database.dart';
import 'package:qr_ops/data/sqlite_qr_record_repository.dart';
import 'package:qr_ops/features/qr_scan/qr_scan_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late SqliteQrRecordRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    // Controller.dispose sends a stop call even though this test intentionally
    // uses the unsupported-platform UI instead of initializing a real camera.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(
            'dev.steenbakker.mobile_scanner/scanner/method',
          ),
          (call) async => null,
        );
  });

  setUp(() async {
    database = await AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    ).open();
    repository = SqliteQrRecordRepository(database);
  });

  tearDown(() => database.close());

  testWidgets(
    'navigation opens implemented QR creation and local history areas',
    (tester) async {
      // The navigation test checks routing, not camera hardware or the plugin.
      // On Windows the page presents its supported-platform message and does
      // not initialize MobileScanner or request a camera stream.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(QrOpsApp(repository: repository));

        expect(find.byType(NavigationRail), findsOneWidget);

        expect(
          find.text('Sua base para operações com códigos QR.'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('nav-criar')));
        await tester.pumpAndSettle();
        expect(find.text('Criar QR Code'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('nav-ler')));
        // Avoid settling animation frames indefinitely while an IndexedStack
        // child contains camera-related progress indicators.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Ler código'), findsOneWidget);
        expect(find.byType(QrScanPage), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('nav-organizar')));
        await tester.pumpAndSettle();
        expect(find.text('Histórico local'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('uses bottom navigation on a narrow screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(QrOpsApp(repository: repository));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(
      find.text('Sua base para operações com códigos QR.'),
      findsOneWidget,
    );
  });

  testWidgets('creates a QR and exposes it in the local history', (
    tester,
  ) async {
    await tester.pumpWidget(QrOpsApp(repository: repository));

    await tester.tap(find.byKey(const ValueKey('nav-criar')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('qr-content-field')),
      'https://example.com/qr-ops',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('qr-preview')), findsOneWidget);
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('qr-save-button')));
    await tester.tap(find.byKey(const ValueKey('qr-save-button')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('QR Code salvo no histórico local.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-organizar')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.text('https://example.com/qr-ops'), findsOneWidget);
    final saved = await tester.runAsync(repository.listLatest);
    expect(saved, hasLength(1));
  });
}
