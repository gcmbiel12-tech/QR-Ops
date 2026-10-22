import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/app/qr_ops_app.dart';
import 'package:qr_ops/domain/qr_record.dart';
import 'package:qr_ops/domain/qr_record_repository.dart';
import 'package:qr_ops/features/qr_create/qr_create_page.dart';
import 'package:qr_ops/features/qr_create/qr_code_preview.dart';
import 'package:qr_ops/features/qr_create/qr_creation_service.dart';
import 'package:qr_ops/features/qr_create/qr_visual_config.dart';

void main() {
  testWidgets('fits a phone browser and creates a local QR record', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _MemoryQrRecordRepository();

    await tester.pumpWidget(QrOpsApp(repository: repository));
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-criar')));
    await tester.pumpAndSettle();

    // Seleciona o tipo de conteúdo.
    await tester.tap(find.byKey(const ValueKey('qr-type-text')));
    await tester.pumpAndSettle();

    // Preenche o conteúdo.
    await tester.enterText(
      find.byKey(const ValueKey('qr-content-field')),
      'QR Ops no navegador',
    );
    await tester.pumpAndSettle();

    // O QR não deve aparecer antes de clicar em Criar QR.
    expect(find.byKey(const ValueKey('qr-preview')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('qr-create-button')));
    await tester.tap(find.byKey(const ValueKey('qr-create-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('qr-preview')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('qr-save-button')));
    await tester.tap(find.byKey(const ValueKey('qr-save-button')));
    await tester.pumpAndSettle();

    expect(repository.records, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('nav-organizar')));
    await tester.pumpAndSettle();

    expect(find.text('QR Ops no navegador'), findsOneWidget);
  });

  testWidgets('uses desktop navigation in a wide browser viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(QrOpsApp(repository: _MemoryQrRecordRepository()));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('rejects an incomplete URL without preview or history save', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _MemoryQrRecordRepository();
    await tester.pumpWidget(QrOpsApp(repository: repository));
    await tester.tap(find.byKey(const ValueKey('nav-criar')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('qr-type-url')));
    await tester.tap(find.byKey(const ValueKey('qr-type-url')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('qr-content-field-url')),
      'exemplo.com',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('qr-create-button')));
    await tester.tap(find.byKey(const ValueKey('qr-create-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('A URL precisa começar com http:// ou https://.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('qr-preview')), findsNothing);
    expect(find.byKey(const ValueKey('qr-save-button')), findsNothing);
    expect(repository.records, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('qr-content-field-url')))
          .controller!
          .text,
      'exemplo.com',
    );

    await tester.enterText(
      find.byKey(const ValueKey('qr-content-field-url')),
      'https://example.com/%zz',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('qr-create-button')));
    await tester.tap(find.byKey(const ValueKey('qr-create-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('A URL está malformada ou contém caracteres inválidos.'),
      findsOneWidget,
    );
    expect(
      find.text('A URL precisa começar com http:// ou https://.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('qr-preview')), findsNothing);
    expect(find.byKey(const ValueKey('qr-save-button')), findsNothing);
    expect(repository.records, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('qr-content-field-url')))
          .controller!
          .text,
      'https://example.com/%zz',
    );
  });

  testWidgets('downloads the generated PNG without saving to history', (
    tester,
  ) async {
    final repository = _MemoryQrRecordRepository();
    Uint8List? downloadedBytes;
    String? downloadedFilename;
    final pngFixture = Uint8List.fromList(
      base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jS8cAAAAASUVORK5CYII=',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QrCreatePage(
            service: QrCreationService(repository),
            onRecordCreated: () {},
            pngExportHandler: (_) async => pngFixture,
            downloadHandler: (bytes, {required filename}) async {
              downloadedBytes = bytes;
              downloadedFilename = filename;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('qr-download-png-button')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('qr-type-text')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('qr-content-field')),
      'Baixar sem salvar',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('qr-create-button')));
    await tester.tap(find.byKey(const ValueKey('qr-create-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('qr-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-save-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('qr-download-png-button')),
      findsOneWidget,
    );
    expect(repository.records, isEmpty);

    await tester.ensureVisible(
      find.byKey(const ValueKey('qr-download-png-button')),
    );
    await tester.tap(find.byKey(const ValueKey('qr-download-png-button')));
    await tester.pumpAndSettle();

    expect(downloadedBytes, isNotNull);
    expect(downloadedBytes!.take(8).toList(), [
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
    ]);
    expect(downloadedFilename, 'qr-code.png');
    expect(find.byKey(const ValueKey('qr-preview')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('qr-content-field')))
          .controller!
          .text,
      'Baixar sem salvar',
    );
    expect(repository.records, isEmpty);
  });

  testWidgets('shows a clear message when PNG download fails', (tester) async {
    final repository = _MemoryQrRecordRepository();
    final pngFixture = Uint8List.fromList(
      base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jS8cAAAAASUVORK5CYII=',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QrCreatePage(
            service: QrCreationService(repository),
            onRecordCreated: () {},
            pngExportHandler: (_) async => pngFixture,
            downloadHandler: (bytes, {required filename}) async {
              throw StateError('Download failed');
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('qr-type-text')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('qr-content-field')),
      'Conteúdo válido',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('qr-create-button')));
    await tester.tap(find.byKey(const ValueKey('qr-create-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('qr-download-png-button')),
    );
    await tester.tap(find.byKey(const ValueKey('qr-download-png-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível baixar o PNG. Tente novamente.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('qr-preview')), findsOneWidget);
    expect(repository.records, isEmpty);
  });

  testWidgets('creates and saves a phone QR from the structured form', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _MemoryQrRecordRepository();

    await tester.pumpWidget(QrOpsApp(repository: repository));

    await tester.tap(find.byKey(const ValueKey('nav-criar')));
    await tester.pumpAndSettle();

    // Seleciona Telefone diretamente na tela de tipos.
    await tester.ensureVisible(find.byKey(const ValueKey('qr-type-phone')));
    await tester.tap(find.byKey(const ValueKey('qr-type-phone')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('qr-content-field-phone')),
      '+55 (11) 99999-0000',
    );
    await tester.pumpAndSettle();

    // A criação deve ser explícita.
    expect(find.byKey(const ValueKey('qr-preview')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('qr-create-button')));
    await tester.tap(find.byKey(const ValueKey('qr-create-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('qr-preview')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('qr-save-button')));
    await tester.tap(find.byKey(const ValueKey('qr-save-button')));
    await tester.pumpAndSettle();

    expect(repository.records, hasLength(1));
    expect(repository.records.single.content, 'tel:+5511999990000');
    expect(repository.records.single.contentType, 'phone');
  });

  testWidgets('visual model changes style without changing entered content', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QrCreatePage(
            service: QrCreationService(_MemoryQrRecordRepository()),
            onRecordCreated: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('qr-type-text')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('qr-content-field')),
      'Conteúdo que deve ser preservado',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('qr-model-creator-pop')),
    );
    await tester.tap(find.byKey(const ValueKey('qr-model-creator-pop')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('qr-content-field')))
          .controller!
          .text,
      'Conteúdo que deve ser preservado',
    );

    await tester.ensureVisible(find.byKey(const ValueKey('qr-create-button')));
    await tester.ensureVisible(find.byKey(const ValueKey('qr-create-button')));
    await tester.tap(find.byKey(const ValueKey('qr-create-button')));
    await tester.pumpAndSettle();

    final preview = tester.widget<QrCodePreview>(find.byType(QrCodePreview));
    expect(preview.frame, QrFrameStyle.stars);
    expect(preview.callToAction, '');
    expect(
      preview.foreground,
      QrVisualLibrary.palette('purple-pink').foreground,
    );
    expect(find.byKey(const ValueKey('qr-preview')), findsOneWidget);
  });
}

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
  Future<QrRecord?> findById(String id) async {
    for (final record in records) {
      if (record.id == id) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<bool> deleteById(String id) async {
    final oldLength = records.length;
    records.removeWhere((record) => record.id == id);
    return records.length < oldLength;
  }
}
