import 'package:idb_shim/idb_browser.dart';

import '../domain/qr_sync_contract.dart';
import 'indexed_db_qr_sync_outbox.dart';

Future<PersistentQrSyncOutbox> openQrSyncOutbox() async =>
    IndexedDbQrSyncOutbox(factory: idbFactoryBrowser);
