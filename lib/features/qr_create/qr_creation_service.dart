import 'package:qr/qr.dart';

import '../../domain/qr_record.dart';
import '../../domain/qr_record_repository.dart';

enum QrContentProblem { empty, tooLong }

class QrContentException implements Exception {
  const QrContentException(this.problem);

  final QrContentProblem problem;
}

class QrCreationService {
  const QrCreationService(this._repository);

  final QrRecordRepository _repository;

  QrImage encode(String content) {
    if (content.trim().isEmpty) {
      throw const QrContentException(QrContentProblem.empty);
    }

    try {
      final code = QrCode(
        payload: QrPayload.fromString(content),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      );
      return QrImage(code);
    } on InputTooLongException {
      throw const QrContentException(QrContentProblem.tooLong);
    }
  }

  Future<QrRecord> create(String content) async {
    encode(content);
    return _repository.insert(QrRecord.created(content: content));
  }
}
