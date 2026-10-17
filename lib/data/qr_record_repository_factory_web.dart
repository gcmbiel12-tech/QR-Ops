import 'package:idb_shim/idb_browser.dart';

import '../domain/qr_record_repository.dart';
import 'indexed_db_qr_record_repository.dart';

Future<QrRecordRepository> openQrRecordRepository() async =>
    IndexedDbQrRecordRepository(factory: idbFactoryBrowser);
