import 'qr_record.dart';

abstract interface class QrRecordRepository {
  Future<QrRecord> insert(QrRecord record);

  Future<List<QrRecord>> listLatest({int limit = 100});

  Future<QrRecord?> findById(String id);

  /// Returns true if an entry was deleted. History entries cannot be updated.
  Future<bool> deleteById(String id);

  /// Updates a saved record while preserving its identity and original timestamp.
  Future<bool> updateById(QrRecord record);

  /// Removes read-history entries strictly older than [cutoffUtc].
  /// Created library entries are never affected.
  Future<int> pruneReadHistoryBefore(DateTime cutoffUtc);

  /// Deletes only read-history entries; saved QR Code entries are preserved.
  Future<int> deleteAllReadHistory();
}
