import '../domain/qr_record_repository.dart';
import '../domain/sync_owner_context.dart';
import 'qr_record_repository_factory_stub.dart'
    if (dart.library.io) 'qr_record_repository_factory_io.dart'
    if (dart.library.js_interop) 'qr_record_repository_factory_web.dart'
    as platform;

Future<QrRecordRepository> openQrRecordRepository({
  SyncOwnerContext? syncOwnerContext,
}) => platform.openQrRecordRepository(syncOwnerContext: syncOwnerContext);
