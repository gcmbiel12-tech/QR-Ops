import '../domain/qr_sync_contract.dart';

Future<PersistentQrSyncOutbox> openQrSyncOutbox() => Future.error(
  UnsupportedError('Esta plataforma não tem fila de sincronização configurada.'),
);
