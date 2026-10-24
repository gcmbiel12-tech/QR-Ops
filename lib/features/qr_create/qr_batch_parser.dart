/// Parses manually supplied identifiers for QR batch creation.
///
/// Numeric ranges are expanded only when a token consists entirely of two
/// decimal integers separated by one hyphen. The default hard limit prevents
/// accidental expansion of enormous ranges on the UI isolate.
class QrBatchParseResult {
  const QrBatchParseResult({
    required this.items,
    required this.duplicates,
    required this.errors,
  });

  final List<String> items;
  final List<String> duplicates;
  final List<String> errors;

  bool get canContinue => items.isNotEmpty && errors.isEmpty;
}

class QrBatchParser {
  const QrBatchParser({this.maxItems = 500}) : assert(maxItems > 0);

  final int maxItems;

  QrBatchParseResult parse(String input, {bool hyphenIsLiteral = false}) {
    final errors = <String>[];
    final items = <String>[];
    final seen = <String>{};
    final duplicates = <String>{};
    final tokens = input.split(RegExp(r'[\r\n,;]+'));

    for (final rawToken in tokens) {
      final token = rawToken.trim();
      if (token.isEmpty) continue;

      // Supports pure numeric ranges (1-10) and identifiers with a shared
      // alphanumeric prefix (A1-A10, ITEM001-ITEM010). The prefix must match
      // exactly on both sides to avoid interpreting ordinary hyphenated codes
      // such as ABC-001 as a range.
      final range = hyphenIsLiteral
          ? null
          : RegExp(r'^(.*?)(\d+)-\1(\d+)$').firstMatch(token);
      if (range == null) {
        if (items.length >= maxItems) {
          errors.add('O lote excede o limite de $maxItems itens.');
          break;
        }
        items.add(token);
        if (!seen.add(token)) duplicates.add(token);
        continue;
      }

      final prefix = range.group(1)!;
      final startText = range.group(2)!;
      final endText = range.group(3)!;
      final start = int.tryParse(startText);
      final end = int.tryParse(endText);
      if (start == null || end == null) {
        errors.add('Intervalo numérico inválido: $token.');
        continue;
      }
      if (end < start) {
        errors.add('O intervalo $token está invertido.');
        continue;
      }
      final count = end - start + 1;
      if (count > maxItems || items.length + count > maxItems) {
        errors.add(
          'O intervalo $token ultrapassa o limite de $maxItems itens.',
        );
        break;
      }
      final preserveWidth =
          startText.startsWith('0') || endText.startsWith('0');
      final width = startText.length > endText.length
          ? startText.length
          : endText.length;
      for (var value = start; value <= end; value++) {
        final suffix = value.toString();
        final item =
            '$prefix${preserveWidth ? suffix.padLeft(width, '0') : suffix}';
        items.add(item);
        if (!seen.add(item)) duplicates.add(item);
      }
    }

    if (items.isEmpty && errors.isEmpty) {
      errors.add('Informe ao menos um código para continuar.');
    }
    return QrBatchParseResult(
      items: List.unmodifiable(items),
      duplicates: List.unmodifiable(duplicates),
      errors: List.unmodifiable(errors),
    );
  }
}
