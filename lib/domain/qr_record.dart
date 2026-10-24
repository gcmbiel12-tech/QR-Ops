import 'package:uuid/uuid.dart';

enum QrRecordOperation { create, read }

const _uuid = Uuid();

/// A local history entry. [revision] is the last server revision observed;
/// zero means the record has not yet been acknowledged by the remote server.
class QrRecord {
  const QrRecord({
    required this.id,
    required this.operation,
    required this.symbology,
    required this.contentType,
    required this.content,
    this.name = '',
    this.description = '',
    required this.createdAt,
    this.revision = 0,
  }) : assert(revision >= 0);

  factory QrRecord.created({
    required String content,
    String contentType = 'text',
    String name = '',
    String description = '',
    DateTime? createdAt,
  }) {
    return QrRecord(
      id: _uuid.v4(),
      operation: QrRecordOperation.create,
      symbology: 'qr',
      contentType: contentType,
      content: content,
      name: name,
      description: description,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );
  }

  factory QrRecord.read({
    required String content,
    required String symbology,
    String contentType = 'text',
    String name = '',
    String description = '',
    DateTime? createdAt,
  }) {
    return QrRecord(
      id: _uuid.v4(),
      operation: QrRecordOperation.read,
      symbology: symbology,
      contentType: contentType,
      content: content,
      name: name,
      description: description,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Generated locally so the ID remains stable if the record is later synced.
  final String id;
  final QrRecordOperation operation;
  final String symbology;
  final String contentType;
  final String content;
  final String name;
  final String description;
  final DateTime createdAt;
  final int revision;

  QrRecord withRevision(int value) => QrRecord(
    id: id,
    operation: operation,
    symbology: symbology,
    contentType: contentType,
    content: content,
    name: name,
    description: description,
    createdAt: createdAt,
    revision: value,
  );
}
