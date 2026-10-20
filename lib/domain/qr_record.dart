import 'package:uuid/uuid.dart';

enum QrRecordOperation { create, read }

const _uuid = Uuid();

/// A local history entry. Persisted entries are immutable.
class QrRecord {
  const QrRecord({
    required this.id,
    required this.operation,
    required this.symbology,
    required this.contentType,
    required this.content,
    required this.createdAt,
  });

  factory QrRecord.created({required String content, DateTime? createdAt}) {
    return QrRecord(
      id: _uuid.v4(),
      operation: QrRecordOperation.create,
      symbology: 'qr',
      contentType: 'text',
      content: content,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );
  }

  factory QrRecord.read({
    required String content,
    required String symbology,
    DateTime? createdAt,
  }) {
    return QrRecord(
      id: _uuid.v4(),
      operation: QrRecordOperation.read,
      symbology: symbology,
      contentType: 'text',
      content: content,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Generated locally so the ID remains stable if the record is later synced.
  final String id;
  final QrRecordOperation operation;
  final String symbology;
  final String contentType;
  final String content;
  final DateTime createdAt;
}
