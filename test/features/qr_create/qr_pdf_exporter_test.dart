import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr_ops/features/qr_create/qr_pdf_exporter.dart';

void main() {
  test('exports a single-page A4 PDF with the rendered QR image', () async {
    final source = img.Image(width: 32, height: 32);
    final pngBytes = Uint8List.fromList(img.encodePng(source));

    final pdfBytes = await const QrPdfExporter().export(pngBytes);
    final pdf = latin1.decode(pdfBytes);

    expect(pdf.startsWith('%PDF-1.4'), isTrue);
    expect(pdf, contains('/MediaBox [0 0 595.28 841.89]'));
    expect(pdf, contains('/Filter /DCTDecode'));
    expect(pdf, contains('/Count 1'));
    expect(pdf.endsWith('%%EOF'), isTrue);
  });

  test('rejects invalid image bytes', () async {
    expect(
      () => const QrPdfExporter().export(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
