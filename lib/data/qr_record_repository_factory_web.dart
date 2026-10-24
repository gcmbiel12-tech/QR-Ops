import 'package:idb_shim/idb_browser.dart';

import '../domain/qr_record_repository.dart';
import '../domain/sync_owner_context.dart';
import 'indexed_db_qr_record_repository.dart';

Future<QrRecordRepository> openQrRecordRepository({
  SyncOwnerContext? syncOwnerContext,
}) async => IndexedDbQrRecordRepository(
  factory: idbFactoryBrowser,
  syncOwnerContext: syncOwnerContext,
);
