import '../domain/qr_record_repository.dart';

Future<QrRecordRepository> openQrRecordRepository() => Future.error(
  UnsupportedError('Esta plataforma não tem armazenamento configurado.'),
);
