String formatRecognizedOcrText(String text) {
  final normalized = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
  if (normalized.isEmpty) return '';

  final lines = normalized.split('\n').map((line) => line.trim()).toList();
  final blocks = <String>[];
  var paragraph = <String>[];

  bool isPageMarker(String line) => RegExp(
    r'^---\s*P(?:a|\u00E1)gina\s+\d+\s*---$',
    caseSensitive: false,
  ).hasMatch(line);

  bool isListItem(String line) =>
      RegExp(r'^(?:[-*]|\u2022|\u25CF|\u25AA|\u25E6|\d+[.)]|[a-zA-Z][.)])\s+')
          .hasMatch(line);

  bool isTableRow(String line) =>
      line.contains('\t') ||
      (line.contains('|') && line.split('|').length >= 3);

  bool isHeading(String line) {
    if (line.length > 90 || line.contains(RegExp(r'[.!?]$'))) return false;
    final letters = line.replaceAll(RegExp(r'[^A-Za-z\u00C0-\u024F]'), '');
    if (letters.length < 3) return false;
    return line.endsWith(':') ||
        (letters == letters.toUpperCase() &&
            RegExp(r'[A-Z]').hasMatch(letters));
  }

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    var joined = '';
    for (final line in paragraph) {
      if (joined.isEmpty) {
        joined = line;
      } else if (RegExp(r'[-\u2010\u2011]$').hasMatch(joined) &&
          RegExp(r'^[a-z\u00E0-\u00F6\u00F8-\u00FF]').hasMatch(line)) {
        joined = joined.substring(0, joined.length - 1) + line;
      } else {
        joined = '$joined $line';
      }
    }
    blocks.add(joined);
    paragraph = [];
  }

  for (final line in lines) {
    if (line.isEmpty) {
      flushParagraph();
      continue;
    }

    if (isPageMarker(line) ||
        isListItem(line) ||
        isTableRow(line) ||
        isHeading(line)) {
      flushParagraph();
      blocks.add(line);
      continue;
    }

    paragraph.add(line);
  }

  flushParagraph();
  return blocks.join('\n\n');
}
