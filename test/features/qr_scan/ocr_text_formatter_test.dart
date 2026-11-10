import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/features/qr_scan/ocr_text_formatter.dart';

void main() {
  group('formatRecognizedOcrText', () {
    test('joins wrapped lines and preserves paragraph boundaries', () {
      final result = formatRecognizedOcrText(
        'Era um dia de domingo, lindo e\n'
        'ensolarado,\n'
        'com muitos pássaros\n'
        'voando no céu do Rio Grande do\n'
        'Norte.\n\n'
        'João e seu filho Diego saíram para\n'
        'pescar como sempre faziam.',
      );

      expect(
        result,
        'Era um dia de domingo, lindo e ensolarado, com muitos pássaros '
        'voando no céu do Rio Grande do Norte.\n\n'
        'João e seu filho Diego saíram para pescar como sempre faziam.',
      );
    });

    test('keeps headings and list items on separate lines', () {
      final result = formatRecognizedOcrText(
        'INFORMAÇÕES GERAIS\n'
        'Nome do documento\n'
        'Itens encontrados:\n'
        '1. Primeiro item\n'
        '2. Segundo item\n'
        'Texto complementar.',
      );

      expect(
        result,
        'INFORMAÇÕES GERAIS\n\n'
        'Nome do documento\n\n'
        'Itens encontrados:\n\n'
        '1. Primeiro item\n\n'
        '2. Segundo item\n\n'
        'Texto complementar.',
      );
    });

    test('preserves table-like rows and PDF page markers', () {
      final result = formatRecognizedOcrText(
        '--- Página 1 ---\n'
        'Código | Descrição | Quantidade\n'
        'A1 | Peça | 10\n'
        '--- Página 2 ---\n'
        'Observações.',
      );

      expect(
        result,
        '--- Página 1 ---\n\n'
        'Código | Descrição | Quantidade\n\n'
        'A1 | Peça | 10\n\n'
        '--- Página 2 ---\n\n'
        'Observações.',
      );
    });

    test('joins words split by end-of-line hyphenation', () {
      expect(
        formatRecognizedOcrText('reconheci-\nmento automático'),
        'reconhecimento automático',
      );
    });

    test('returns empty text for empty input', () {
      expect(formatRecognizedOcrText('  \n  '), isEmpty);
    });
  });
}
