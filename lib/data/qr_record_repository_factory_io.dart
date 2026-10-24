import '../domain/qr_record_repository.dart';
import '../domain/sync_owner_context.dart';
import 'app_database.dart';
import 'sqlite_qr_record_repository.dart';

Future<QrRecordRepository> openQrRecordRepository({
  SyncOwnerContext? syncOwnerContext,
}) async {
  final database = await AppDatabase.openDefault();
  return SqliteQrRecordRepository(database, syncOwnerContext: syncOwnerContext);
}
