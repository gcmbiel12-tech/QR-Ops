import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/domain/qr_content_interpreter.dart';

void main() {
  const interpreter = QrContentInterpreter();

  test('recognizes only valid HTTP(S) URLs as links', () {
    expect(
      interpreter.interpret('https://example.com/a').kind,
      QrContentKind.url,
    );
    expect(
      interpreter.interpret('javascript:alert(1)').kind,
      QrContentKind.text,
    );
    expect(interpreter.interpret('example.com/path').kind, QrContentKind.text);
    expect(interpreter.interpret('https://').kind, QrContentKind.text);
  });

  test('recognizes telephone and email content without executing it', () {
    expect(
      interpreter.interpret('tel:+15551234567').uri.toString(),
      'tel:+15551234567',
    );
    expect(
      interpreter.interpret('+1 (555) 123-4567').kind,
      QrContentKind.phone,
    );
    expect(
      interpreter.interpret('mailto:ops@example.com').kind,
      QrContentKind.email,
    );
    expect(interpreter.interpret('ops@example.com').kind, QrContentKind.email);
  });

  test('recognizes WhatsApp and legacy SMS schemes', () {
    expect(
      interpreter.interpret('whatsapp://send?phone=15551234567').kind,
      QrContentKind.whatsapp,
    );
    expect(interpreter.interpret('sms:+15551234567').kind, QrContentKind.sms);
  });

  test('parses Wi-Fi fields without attempting to connect', () {
    final result = interpreter.interpret(
      r'WIFI:T:WPA;S:Office\; East;P:secret;;',
    );
    expect(result.kind, QrContentKind.wifi);
    expect(result.fields['T'], 'WPA');
    expect(result.fields['S'], 'Office; East');
    expect(result.fields['P'], 'secret');
  });

  test('recognizes vCard fields and preserves unknown raw content', () {
    final contact = interpreter.interpret(
      'BEGIN:VCARD\nFN:Ana Silva\nTEL:+15551234567\nEMAIL:ana@example.com\nEND:VCARD',
    );
    expect(contact.kind, QrContentKind.vcard);
    expect(contact.fields['Nome'], 'Ana Silva');
    expect(contact.fields['Telefone'], '+15551234567');
    expect(contact.fields['E-mail'], 'ana@example.com');
    expect(interpreter.interpret('arbitrary payload').kind, QrContentKind.text);
  });
}
