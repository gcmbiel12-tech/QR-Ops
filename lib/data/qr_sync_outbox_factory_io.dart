import '../domain/qr_sync_contract.dart';
import 'app_database.dart';
import 'sqlite_qr_sync_outbox.dart';

Future<PersistentQrSyncOutbox> openQrSyncOutbox() async {
  final database = await AppDatabase.openDefault();
  return SqliteQrSyncOutbox(database);
}
