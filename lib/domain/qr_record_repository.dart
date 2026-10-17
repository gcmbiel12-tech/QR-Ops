import 'qr_record.dart';

abstract interface class QrRecordRepository {
  Future<QrRecord> insert(QrRecord record);

  Future<List<QrRecord>> listLatest({int limit = 100});

  Future<QrRecord?> findById(String id);

  /// Returns true if an entry was deleted. History entries cannot be updated.
  Future<bool> deleteById(String id);
}
