import '../domain/qr_record_repository.dart';
import '../domain/sync_owner_context.dart';

Future<QrRecordRepository> openQrRecordRepository({
  SyncOwnerContext? syncOwnerContext,
}) => Future.error(
  UnsupportedError('Esta plataforma não tem armazenamento configurado.'),
);
