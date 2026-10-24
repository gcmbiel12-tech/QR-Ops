import '../domain/qr_sync_contract.dart';
import 'qr_sync_outbox_factory_stub.dart'
    if (dart.library.io) 'qr_sync_outbox_factory_io.dart'
    if (dart.library.js_interop) 'qr_sync_outbox_factory_web.dart'
    as platform;

Future<PersistentQrSyncOutbox> openQrSyncOutbox() =>
    platform.openQrSyncOutbox();
