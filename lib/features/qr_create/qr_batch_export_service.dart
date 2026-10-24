import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_saver/file_saver.dart';
import 'package:qr/qr.dart';

import 'qr_creation_service.dart';
import 'qr_png_exporter.dart';

class QrBatchExportService {
  const QrBatchExportService({this.pngExporter = const QrPngExporter()});

  final QrPngExporter pngExporter;

  int resolutionForSize(String size) => switch (size) {
    'Pequeno' => 512,
    'Grande' => 2048,
    _ => 1024,
  };

  double printSizeFor(String size) => switch (size) {
    'Pequeno' => 68,
    'Grande' => 108,
    _ => 88,
  };

  Future<Uint8List> buildZip(
    List<String> contents,
    QrCreationService service, {
    String size = 'Médio',
  }) async {
    if (contents.isEmpty) throw ArgumentError('Selecione ao menos um QR Code.');
    final archive = Archive();
    final usedNames = <String, int>{};
    final resolution = resolutionForSize(size);
    for (var i = 0; i < contents.length; i++) {
      final content = contents[i];
      final baseName = _safeName(content, i + 1);
      final duplicateCount = (usedNames[baseName] ?? 0) + 1;
      usedNames[baseName] = duplicateCount;
      final filename =
          '${duplicateCount == 1 ? baseName : '$baseName-$duplicateCount'}.png';
      final image = service.encode(content);
      final bytes = await pngExporter.export(image, dimension: resolution);
      archive.addFile(ArchiveFile(filename, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<void> saveZip(
    List<String> contents,
    QrCreationService service, {
    String size = 'Médio',
  }) async {
    final bytes = await buildZip(contents, service, size: size);
    await FileSaver.instance.saveFile(
      name: 'qr-ops-codigos',
      bytes: bytes,
      fileExtension: 'zip',
      mimeType: MimeType.zip,
    );
  }

  Uint8List buildPdf(
    List<String> contents,
    QrCreationService service, {
    String size = 'Médio',
    bool labelSheet = true,
  }) {
    if (contents.isEmpty) throw ArgumentError('Selecione ao menos um QR Code.');
    const pageWidth = 595.0;
    const pageHeight = 842.0;
    final qrSize = printSizeFor(size);
    final perPage = labelSheet ? 12 : 2;
    final pageCount = (contents.length / perPage).ceil();
    final objects = <String>[''];

    int addObject(String value) {
      objects.add(value);
      return objects.length - 1;
    }

    final catalogId = addObject('');
    final pagesId = addObject('');
    final fontId = addObject(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    );
    final pageIds = <int>[];

    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final commands = StringBuffer()
        ..writeln('1 1 1 rg 0 0 $pageWidth $pageHeight re f');
      final start = pageIndex * perPage;
      final end = (start + perPage).clamp(0, contents.length);
      for (var index = start; index < end; index++) {
        final localIndex = index - start;
        late final double centerX;
        late final double top;
        late final double cellWidth;
        if (labelSheet) {
          const margin = 22.0;
          const columns = 3;
          const cellHeight = 198.0;
          cellWidth = (pageWidth - margin * 2) / columns;
          final column = localIndex % columns;
          final row = localIndex ~/ columns;
          centerX = margin + cellWidth * (column + 0.5);
          top = pageHeight - 24 - row * cellHeight;
        } else {
          cellWidth = pageWidth - 48;
          centerX = pageWidth / 2;
          top = pageHeight - 34 - localIndex * 400;
        }
        final actualSize = labelSheet ? qrSize : qrSize * 1.65;
        final qrTop = top - actualSize;
        _drawQr(
          commands,
          service.encode(contents[index]),
          centerX - actualSize / 2,
          qrTop,
          actualSize,
        );
        final label = _safePdfText(
          contents[index],
          maxLength: labelSheet ? 38 : 90,
        );
        final fontSize = labelSheet ? 8.0 : 11.0;
        final baseline = qrTop - (labelSheet ? 14 : 22);
        commands.writeln(
          '0 0 0 rg BT /F1 $fontSize Tf ${centerX - (label.length * fontSize * 0.22)} $baseline Td (${_escapePdf(label)}) Tj ET',
        );
        if (!labelSheet) {
          commands.writeln(
            '0 0 0 rg BT /F1 8 Tf 24 ${baseline - 14} Td (Item ${index + 1} de ${contents.length}) Tj ET',
          );
        }
      }
      commands.writeln(
        '0 0 0 rg BT /F1 8 Tf 24 16 Td (QR Ops - ${pageIndex + 1}/$pageCount) Tj ET',
      );
      final stream = ascii.encode(commands.toString());
      final contentId = addObject(
        '<< /Length ${stream.length} >>\nstream\n${commands.toString()}endstream',
      );
      final pageId = addObject(
        '<< /Type /Page /Parent $pagesId 0 R /MediaBox [0 0 $pageWidth $pageHeight] /Resources << /Font << /F1 $fontId 0 R >> >> /Contents $contentId 0 R >>',
      );
      pageIds.add(pageId);
    }

    objects[catalogId] = '<< /Type /Catalog /Pages $pagesId 0 R >>';
    objects[pagesId] =
        '<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] /Count ${pageIds.length} >>';

    final output = BytesBuilder(copy: false);
    final offsets = <int>[0];
    var length = 0;
    void writeAscii(String value) {
      final bytes = ascii.encode(value);
      output.add(bytes);
      length += bytes.length;
    }

    writeAscii('%PDF-1.4\n%QR Ops\n');
    for (var id = 1; id < objects.length; id++) {
      offsets.add(length);
      writeAscii('$id 0 obj\n${objects[id]}\nendobj\n');
    }
    final xrefOffset = length;
    writeAscii('xref\n0 ${objects.length}\n0000000000 65535 f \n');
    for (var id = 1; id < offsets.length; id++) {
      writeAscii('${offsets[id].toString().padLeft(10, '0')} 00000 n \n');
    }
    writeAscii(
      'trailer\n<< /Size ${objects.length} /Root $catalogId 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
    );
    return output.takeBytes();
  }

  Future<void> savePdf(
    List<String> contents,
    QrCreationService service, {
    String size = 'Médio',
    bool labelSheet = true,
  }) async {
    final bytes = buildPdf(
      contents,
      service,
      size: size,
      labelSheet: labelSheet,
    );
    await FileSaver.instance.saveFile(
      name: labelSheet ? 'qr-ops-folha-etiquetas' : 'qr-ops-relatorio',
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  void _drawQr(
    StringBuffer commands,
    QrImage image,
    double left,
    double bottom,
    double size,
  ) {
    const quietZone = 4;
    final totalModules = image.moduleCount + quietZone * 2;
    final moduleSize = size / totalModules;
    commands.writeln('0 0 0 rg');
    for (var row = 0; row < image.moduleCount; row++) {
      for (var column = 0; column < image.moduleCount; column++) {
        if (!image.isDark(row, column)) continue;
        final x = left + (column + quietZone) * moduleSize;
        final y =
            bottom + (image.moduleCount - row - 1 + quietZone) * moduleSize;
        commands.writeln(
          '${x.toStringAsFixed(3)} ${y.toStringAsFixed(3)} ${moduleSize.toStringAsFixed(3)} ${moduleSize.toStringAsFixed(3)} re f',
        );
      }
    }
  }

  String _safeName(String content, int index) {
    final normalized = content
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final truncated = normalized.length > 48
        ? normalized.substring(0, 48)
        : normalized;
    return truncated.isEmpty ? 'qr-code-$index' : truncated;
  }

  String _safePdfText(String value, {required int maxLength}) {
    final latinSafe = value.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
    return latinSafe.length > maxLength
        ? '${latinSafe.substring(0, maxLength - 1)}…'.replaceAll('…', '...')
        : latinSafe;
  }

  String _escapePdf(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('(', '\\(')
      .replaceAll(')', '\\)');
}
