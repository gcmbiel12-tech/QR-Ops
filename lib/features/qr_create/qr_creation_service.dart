import 'package:qr/qr.dart';

import '../../domain/qr_record.dart';
import '../../domain/qr_record_repository.dart';

enum QrContentType { text, url, phone, email, sms, wifi }

extension QrContentTypeLabel on QrContentType {
  String get label => switch (this) {
    QrContentType.text => 'Texto livre',
    QrContentType.url => 'Site ou URL',
    QrContentType.phone => 'Telefone',
    QrContentType.email => 'E-mail',
    QrContentType.sms => 'SMS',
    QrContentType.wifi => 'Wi-Fi',
  };

  String get storageValue => name;
}

enum QrContentProblem {
  empty,
  invalid,
  urlSchemeRequired,
  malformedUrl,
  tooLong,
}

class QrContentException implements Exception {
  const QrContentException(this.problem);

  final QrContentProblem problem;
}

class QrContentDraft {
  const QrContentDraft({
    required this.type,
    this.value = '',
    this.secondary = '',
    this.tertiary = '',
    this.wifiSecurity = 'WPA',
    this.hiddenNetwork = false,
  });

  final QrContentType type;
  final String value;
  final String secondary;
  final String tertiary;
  final String wifiSecurity;
  final bool hiddenNetwork;
}

class QrEncodedContent {
  const QrEncodedContent({required this.type, required this.value});

  final QrContentType type;
  final String value;
}

class QrCreationService {
  const QrCreationService(this._repository);

  final QrRecordRepository _repository;

  QrEncodedContent compose(QrContentDraft draft) {
    final value = draft.value.trim();
    if (value.isEmpty) throw const QrContentException(QrContentProblem.empty);

    String content;
    switch (draft.type) {
      case QrContentType.text:
        content = draft.value;
        break;
      case QrContentType.url:
        final uri = Uri.tryParse(value);
        if (uri == null) {
          throw const QrContentException(QrContentProblem.malformedUrl);
        }
        if (!uri.hasScheme ||
            !const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
          throw const QrContentException(QrContentProblem.urlSchemeRequired);
        }
        if (value != draft.value ||
            RegExp(r'\s').hasMatch(value) ||
            RegExp(r'%(?![0-9A-Fa-f]{2})').hasMatch(value) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw const QrContentException(QrContentProblem.malformedUrl);
        }
        // Validate the address, but encode exactly what the user entered.
        content = draft.value;
        break;
      case QrContentType.phone:
        final phone = _phone(value);
        if (phone == null) {
          throw const QrContentException(QrContentProblem.invalid);
        }
        content = 'tel:$phone';
        break;
      case QrContentType.email:
        if (!_validEmail(value)) {
          throw const QrContentException(QrContentProblem.invalid);
        }
        final subject = draft.secondary.trim();
        final body = draft.tertiary;
        final query = <String, String>{
          if (subject.isNotEmpty) 'subject': subject,
          if (body.isNotEmpty) 'body': body,
        };
        content =
            'mailto:$value${query.isEmpty ? '' : '?${_encodeQuery(query)}'}';
        break;
      case QrContentType.sms:
        final phone = _phone(value);
        if (phone == null) {
          throw const QrContentException(QrContentProblem.invalid);
        }
        content = 'sms:$phone';
        if (draft.secondary.isNotEmpty) {
          content += '?body=${Uri.encodeComponent(draft.secondary)}';
        }
        break;
      case QrContentType.wifi:
        final ssid = draft.value;
        final password = draft.secondary;
        final security = draft.wifiSecurity;
        if (ssid.trim().isEmpty ||
            !const {'WPA', 'WEP', 'nopass'}.contains(security) ||
            (security != 'nopass' && password.isEmpty)) {
          throw const QrContentException(QrContentProblem.invalid);
        }
        content =
            'WIFI:T:$security;S:${_escapeWifi(ssid)};'
            '${security == 'nopass' ? '' : 'P:${_escapeWifi(password)};'}'
            '${draft.hiddenNetwork ? 'H:true;' : ''};';
        break;
    }

    return QrEncodedContent(type: draft.type, value: content);
  }

  QrImage encode(String content) {
    if (content.trim().isEmpty) {
      throw const QrContentException(QrContentProblem.empty);
    }
    try {
      final payload = QrPayload.fromString(content);
      if (content.codeUnits.any((unit) => unit > 127 && unit <= 255)) {
        // qr's string helper encodes byte segments as UTF-8, but only adds an
        // ECI marker automatically for code points above Latin-1. Mark Latin-1
        // accents too, so independent readers do not interpret UTF-8 bytes as
        // ISO-8859-1.
        final utf8Payload = QrPayload()
          ..addECI(QrEciValue.utf8)
          ..addString(content);
        return QrImage(
          QrCode(
            payload: utf8Payload,
            errorCorrectLevel: QrErrorCorrectLevel.high,
          ),
        );
      }
      return QrImage(
        QrCode(payload: payload, errorCorrectLevel: QrErrorCorrectLevel.high),
      );
    } on InputTooLongException {
      throw const QrContentException(QrContentProblem.tooLong);
    }
  }

  Future<QrRecord> create(String content, {String contentType = 'text'}) async {
    encode(content);
    return _repository.insert(
      QrRecord.created(content: content, contentType: contentType),
    );
  }

  static String? _phone(String value) {
    final compact = value.replaceAll(RegExp(r'[\s().-]'), '');
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(compact)) return null;
    return compact;
  }

  static bool _validEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  static String _escapeWifi(String value) =>
      value.replaceAllMapped(RegExp(r'([\\;,:])'), (match) => '\\${match[1]}');

  static String _encodeQuery(Map<String, String> values) => values.entries
      .map(
        (entry) =>
            '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
      )
      .join('&');
}
