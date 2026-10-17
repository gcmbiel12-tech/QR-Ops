import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb.dart';
import 'package:idb_shim/idb_browser.dart' show idbFactoryBrowser;
import 'package:qr_ops/data/indexed_db_qr_record_repository.dart';
import 'package:qr_ops/domain/qr_record.dart';

void main() {
  late IndexedDbQrRecordRepository repository;
  late String databaseName;

  setUp(() {
    databaseName = 'qr_ops_test_${DateTime.now().microsecondsSinceEpoch}';
    repository = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
    );
  });

  tearDown(() => repository.deleteDatabase());

  test('inserts and reads the original record fields', () async {
    final record = QrRecord.created(
      content: '  conteúdo original  ',
      createdAt: DateTime.utc(2026, 10, 16, 12, 30),
    );

    final inserted = await repository.insert(record);
    final loaded = await repository.findById(record.id);

    expect(inserted.id, record.id);
    expect(loaded?.id, record.id);
    expect(loaded?.content, '  conteúdo original  ');
    expect(loaded?.createdAt, record.createdAt);
    expect(loaded?.operation, QrRecordOperation.create);
    expect(loaded?.symbology, 'qr');
    expect(loaded?.contentType, 'text');
  });

  test('lists latest records first and applies the requested limit', () async {
    await repository.insert(
      QrRecord.created(
        content: 'mais antigo',
        createdAt: DateTime.utc(2026, 10, 15),
      ),
    );
    await repository.insert(
      QrRecord.created(
        content: 'mais recente',
        createdAt: DateTime.utc(2026, 10, 16),
      ),
    );

    expect(
      (await repository.listLatest(limit: 1)).single.content,
      'mais recente',
    );
    expect(await repository.listLatest(), hasLength(2));
    await expectLater(repository.listLatest(limit: 0), throwsArgumentError);
  });

  test('persists across repository and database re-opening', () async {
    final record = await repository.insert(
      QrRecord.created(content: 'permanece após recarregar'),
    );
    await repository.close();
    repository = IndexedDbQrRecordRepository(
      factory: idbFactoryBrowser,
      databaseName: databaseName,
    );

    final restored = await repository.findById(record.id);
    expect(restored?.id, record.id);
    expect(restored?.content, 'permanece após recarregar');
  });

  test('deletes an existing record and reports missing records', () async {
    final record = await repository.insert(
      QrRecord.created(content: 'remover'),
    );

    expect(await repository.deleteById(record.id), isTrue);
    expect(await repository.findById(record.id), isNull);
    expect(await repository.deleteById(record.id), isFalse);
  });

  test('rejects invalid input and duplicate identifiers', () async {
    await expectLater(
      repository.insert(QrRecord.created(content: '  ')),
      throwsArgumentError,
    );
    final record = await repository.insert(
      QrRecord.created(content: 'conteúdo'),
    );
    await expectLater(repository.insert(record), throwsA(anything));
  });

  test('propagates IndexedDB open failures to the caller', () async {
    final failingRepository = IndexedDbQrRecordRepository(
      factory: _FailingIdbFactory(),
      databaseName: databaseName,
    );

    await expectLater(failingRepository.listLatest(), throwsStateError);
  });

  test(
    'observes failed read transactions and propagates the read error',
    () async {
      final failingRepository = IndexedDbQrRecordRepository(
        factory: _FailingReadIdbFactory(),
        databaseName: databaseName,
      );

      await expectLater(failingRepository.listLatest(), throwsStateError);
      await expectLater(
        failingRepository.findById('missing'),
        throwsStateError,
      );
    },
  );
}

class _FailingIdbFactory extends Fake implements IdbFactory {
  @override
  Future<Database> open(
    String dbName, {
    int? version,
    OnUpgradeNeededFunction? onUpgradeNeeded,
    OnBlockedFunction? onBlocked,
  }) => Future.error(StateError('IndexedDB indisponível'));
}

class _FailingReadIdbFactory extends Fake implements IdbFactory {
  @override
  Future<Database> open(
    String dbName, {
    int? version,
    OnUpgradeNeededFunction? onUpgradeNeeded,
    OnBlockedFunction? onBlocked,
  }) => Future.value(_FailingReadDatabase());
}

class _FailingReadDatabase extends Fake implements Database {
  @override
  Transaction transaction(Object storeNameOrStoreNames, String mode) =>
      _FailingReadTransaction(this);

  @override
  void close() {}
}

class _FailingReadTransaction extends Fake implements Transaction {
  _FailingReadTransaction(this.database);

  @override
  final Database database;

  @override
  ObjectStore objectStore(String name) => _FailingReadObjectStore();

  @override
  Future<Database> get completed =>
      Future.error(StateError('IndexedDB read transaction failed'));

  @override
  Iterable<String> get objectStoreNames => const [_storeNameForTest];

  @override
  void abort() {}
}

class _FailingReadObjectStore extends Fake implements ObjectStore {
  @override
  Future<List<Object>> getAll([Object? query, int? count]) =>
      Future.error(StateError('IndexedDB read failed'));

  @override
  Future<Object?> getObject(Object key) =>
      Future.error(StateError('IndexedDB read failed'));
}

const _storeNameForTest = 'qr_records';
