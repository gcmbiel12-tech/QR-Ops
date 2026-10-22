enum QrContentKind { url, phone, email, whatsapp, wifi, vcard, sms, text }

class QrContentInterpretation {
  const QrContentInterpretation({
    required this.kind,
    required this.rawValue,
    this.uri,
    this.fields = const {},
  });

  final QrContentKind kind;
  final String rawValue;
  final Uri? uri;
  final Map<String, String> fields;

  bool get hasExternalAction => uri != null;
}

/// Conservative, side-effect-free interpretation of data decoded from a code.
/// This class never opens links, sends messages, or joins networks.
class QrContentInterpreter {
  const QrContentInterpreter();

  QrContentInterpretation interpret(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      return QrContentInterpretation(kind: QrContentKind.text, rawValue: value);
    }

    final wifi = _parseWifi(raw);
    if (wifi != null) {
      return QrContentInterpretation(
        kind: QrContentKind.wifi,
        rawValue: value,
        fields: wifi,
      );
    }

    if (raw.toUpperCase().startsWith('BEGIN:VCARD')) {
      return QrContentInterpretation(
        kind: QrContentKind.vcard,
        rawValue: value,
        fields: _parseVcard(raw),
      );
    }

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final scheme = uri.scheme.toLowerCase();
      if ((scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty) {
        if (uri.host.toLowerCase() == 'wa.me' ||
            uri.host.toLowerCase().endsWith('.whatsapp.com')) {
          return QrContentInterpretation(
            kind: QrContentKind.whatsapp,
            rawValue: value,
            uri: uri,
          );
        }
        return QrContentInterpretation(
          kind: QrContentKind.url,
          rawValue: value,
          uri: uri,
        );
      }
      if (scheme == 'tel' && uri.path.isNotEmpty) {
        return QrContentInterpretation(
          kind: QrContentKind.phone,
          rawValue: value,
          uri: uri,
        );
      }
      if (scheme == 'mailto' && uri.path.contains('@')) {
        return QrContentInterpretation(
          kind: QrContentKind.email,
          rawValue: value,
          uri: uri,
        );
      }
      if (scheme == 'sms' && uri.path.isNotEmpty) {
        return QrContentInterpretation(
          kind: QrContentKind.sms,
          rawValue: value,
          uri: uri,
        );
      }
      if (scheme == 'whatsapp' && uri.host == 'send') {
        return QrContentInterpretation(
          kind: QrContentKind.whatsapp,
          rawValue: value,
          uri: uri,
        );
      }
    }

    if (_looksLikePhone(raw)) {
      final phone = raw.replaceAll(RegExp(r'[^+0-9]'), '');
      return QrContentInterpretation(
        kind: QrContentKind.phone,
        rawValue: value,
        uri: Uri(scheme: 'tel', path: phone),
      );
    }
    if (_looksLikeEmail(raw)) {
      return QrContentInterpretation(
        kind: QrContentKind.email,
        rawValue: value,
        uri: Uri(scheme: 'mailto', path: raw),
      );
    }

    return QrContentInterpretation(kind: QrContentKind.text, rawValue: value);
  }

  bool _looksLikePhone(String value) {
    if (!RegExp(r'^[+0-9().\-\s]{7,}$').hasMatch(value)) return false;
    return value.replaceAll(RegExp(r'\D'), '').length >= 7;
  }

  bool _looksLikeEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  Map<String, String> _parseVcard(String value) {
    final fields = <String, String>{};
    for (final line in value.split(RegExp(r'\r?\n'))) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final property = line
          .substring(0, separator)
          .split(';')
          .first
          .toUpperCase();
      const allowed = {'FN', 'N', 'ORG', 'TITLE', 'TEL', 'EMAIL', 'URL'};
      if (!allowed.contains(property)) continue;
      final content = line.substring(separator + 1).trim();
      if (content.isEmpty) continue;
      final label = switch (property) {
        'FN' => 'Nome',
        'N' => 'Nome estruturado',
        'ORG' => 'Organização',
        'TITLE' => 'Cargo',
        'TEL' => 'Telefone',
        'EMAIL' => 'E-mail',
        'URL' => 'Site',
        _ => property,
      };
      fields.putIfAbsent(label, () => content);
    }
    return Map.unmodifiable(fields);
  }

  Map<String, String>? _parseWifi(String value) {
    if (!value.startsWith('WIFI:')) return null;
    final body = value.substring(5);
    final fields = <String, String>{};
    final parts = <String>[];
    final buffer = StringBuffer();
    var escaped = false;
    for (final rune in body.runes) {
      final char = String.fromCharCode(rune);
      if (escaped) {
        buffer.write(char);
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == ';') {
        parts.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) parts.add(buffer.toString());
    for (final part in parts) {
      final separator = part.indexOf(':');
      if (separator <= 0) continue;
      final key = part.substring(0, separator);
      if (const {'S', 'T', 'P', 'H'}.contains(key)) {
        fields[key] = part.substring(separator + 1);
      }
    }
    return fields.containsKey('S') ? Map.unmodifiable(fields) : null;
  }
}
