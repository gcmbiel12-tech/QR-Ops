import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/features/qr_create/qr_batch_parser.dart';

void main() {
  const parser = QrBatchParser(maxItems: 10);

  test('splits lines, commas and semicolons while trimming whitespace', () {
    final result = parser.parse(' A, B; C\nD ');
    expect(result.items, ['A', 'B', 'C', 'D']);
    expect(result.errors, isEmpty);
  });

  test('expands numeric ranges and preserves leading zero width', () {
    final result = parser.parse('0008-0010; 21-22');
    expect(result.items, ['0008', '0009', '0010', '21', '22']);
    expect(result.canContinue, isTrue);
  });

  test('preserves alphanumeric hyphenated identifiers', () {
    final result = parser.parse('ABC-001;X-2');
    expect(result.items, ['ABC-001', 'X-2']);
  });

  test('expands alphanumeric ranges such as A1-A10', () {
    final result = parser.parse('A1-A10');
    expect(result.items, [
      'A1',
      'A2',
      'A3',
      'A4',
      'A5',
      'A6',
      'A7',
      'A8',
      'A9',
      'A10',
    ]);
    expect(result.canContinue, isTrue);
  });

  test('expands shared prefixes and preserves numeric suffix width', () {
    final result = parser.parse('ITEM008-ITEM010');
    expect(result.items, ['ITEM008', 'ITEM009', 'ITEM010']);
    expect(result.canContinue, isTrue);
  });

  test('treats numeric hyphen as literal when explicitly selected', () {
    final result = parser.parse('1001-1003', hyphenIsLiteral: true);
    expect(result.items, ['1001-1003']);
  });

  test('reports reversed ranges', () {
    final result = parser.parse('12-10');
    expect(result.items, isEmpty);
    expect(result.errors, contains('O intervalo 12-10 está invertido.'));
  });

  test('refuses oversized ranges without expanding them', () {
    final result = parser.parse('1-1000000000');
    expect(result.items, isEmpty);
    expect(result.errors, hasLength(1));
    expect(result.errors.single, contains('limite de 10 itens'));
  });

  test('reports duplicates without removing them silently', () {
    final result = parser.parse('A;B;A');
    expect(result.items, ['A', 'B', 'A']);
    expect(result.duplicates, ['A']);
  });

  test('rejects empty input', () {
    final result = parser.parse('  ; ,\n ');
    expect(result.canContinue, isFalse);
    expect(
      result.errors,
      contains('Informe ao menos um código para continuar.'),
    );
  });

  test('enforces the maximum batch size', () {
    final result = parser.parse('1;2;3;4;5;6;7;8;9;10;11');
    expect(result.items, hasLength(10));
    expect(result.errors.single, contains('limite de 10 itens'));
  });

  test('parses 500 identifiable codes and rejects item 501', () {
    const largeParser = QrBatchParser(maxItems: 500);
    final input = List<String>.generate(
      500,
      (index) => 'QR-AUDIT-${(index + 1).toString().padLeft(4, '0')}',
    ).join('\n');
    final result = largeParser.parse(input);
    expect(result.items, hasLength(500));
    expect(result.items.first, 'QR-AUDIT-0001');
    expect(result.items.last, 'QR-AUDIT-0500');
    expect(result.errors, isEmpty);

    final oversized = largeParser.parse('$input\nQR-AUDIT-0501');
    expect(oversized.items, hasLength(500));
    expect(oversized.errors, hasLength(1));
    expect(oversized.errors.single, contains('limite de 500 itens'));
  });
}
