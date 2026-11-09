import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Cria um PDF A4 com o QR Code renderizado em alta resolução.
class QrPdfExporter {
  const QrPdfExporter();

  Future<Uint8List> export(Uint8List pngBytes) async {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) {
      throw const FormatException('Não foi possível processar o QR Code.');
    }

    // O PNG exportado já contém cores, moldura, chamada para ação e logo.
    final jpeg = img.encodeJpg(decoded.convert(numChannels: 3), quality: 96);
    final imageBytes = Uint8List.fromList(jpeg);

    const pageWidth = 595.28; // A4 em pontos.
    const pageHeight = 841.89;
    const imageSide = 360.0;
    const imageX = (pageWidth - imageSide) / 2;
    const imageY = (pageHeight - imageSide) / 2;

    final content = ascii.encode(
      'q\n$imageSide 0 0 $imageSide $imageX $imageY cm\n/QRImage Do\nQ\n',
    );

    final objects = <Uint8List>[
      ascii.encode('<< /Type /Catalog /Pages 2 0 R >>'),
      ascii.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      ascii.encode(
        '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 $pageWidth $pageHeight] '
        '/Resources << /XObject << /QRImage 4 0 R >> >> '
        '/Contents 5 0 R >>',
      ),
      Uint8List.fromList([
        ...ascii.encode(
          '<< /Type /XObject /Subtype /Image '
          '/Width ${decoded.width} /Height ${decoded.height} '
          '/ColorSpace /DeviceRGB /BitsPerComponent 8 '
          '/Filter /DCTDecode /Length ${imageBytes.length} >>\nstream\n',
        ),
        ...imageBytes,
        ...ascii.encode('\nendstream'),
      ]),
      Uint8List.fromList([
        ...ascii.encode('<< /Length ${content.length} >>\nstream\n'),
        ...content,
        ...ascii.encode('endstream'),
      ]),
    ];

    final output = BytesBuilder(copy: false);
    output.add(ascii.encode('%PDF-1.4\n% QR Ops\n'));
    final offsets = <int>[0];
    for (var index = 0; index < objects.length; index++) {
      offsets.add(output.length);
      output.add(ascii.encode('${index + 1} 0 obj\n'));
      output.add(objects[index]);
      output.add(ascii.encode('\nendobj\n'));
    }

    final xrefOffset = output.length;
    output.add(ascii.encode('xref\n0 ${objects.length + 1}\n'));
    output.add(ascii.encode('0000000000 65535 f \n'));
    for (final offset in offsets.skip(1)) {
      output.add(
        ascii.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'),
      );
    }
    output.add(
      ascii.encode(
        'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
        'startxref\n$xrefOffset\n%%EOF',
      ),
    );
    return output.takeBytes();
  }
}
