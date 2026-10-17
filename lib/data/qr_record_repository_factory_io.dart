import '../domain/qr_record_repository.dart';
import 'app_database.dart';
import 'sqlite_qr_record_repository.dart';

Future<QrRecordRepository> openQrRecordRepository() async {
  final database = await AppDatabase.openDefault();
  return SqliteQrRecordRepository(database);
}
