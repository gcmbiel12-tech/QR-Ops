import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late DatabaseFactory factory;

  setUpAll(() {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  });

  test(
    'creates a versioned SQLite database and enables foreign keys',
    () async {
      final database = await AppDatabase(
        factory: factory,
        path: inMemoryDatabasePath,
      ).open();
      addTearDown(database.close);

      expect(await database.getVersion(), AppDatabase.schemaVersion);
      expect(
        await _pragmaValue(database, 'application_id'),
        AppDatabase.applicationId,
      );
      expect(await _pragmaValue(database, 'foreign_keys'), 1);
      expect(
        await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'qr_records'",
        ),
        hasLength(1),
      );
      expect(
        await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'qr_records_created_at_idx'",
        ),
        hasLength(1),
      );
    },
  );

  test(
    'migrates a version one database without dropping existing data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'qr_ops_db_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}qr_ops.db';

      final legacyDatabase = await factory.openDatabase(path);
      await legacyDatabase.execute(
        'CREATE TABLE legacy_fixture (value TEXT NOT NULL)',
      );
      await legacyDatabase.insert('legacy_fixture', {'value': 'preserve-me'});
      await legacyDatabase.execute(
        'PRAGMA application_id = ${AppDatabase.applicationId}',
      );
      await legacyDatabase.setVersion(1);
      await legacyDatabase.close();

      final database = await AppDatabase(factory: factory, path: path).open();
      addTearDown(database.close);

      expect(await database.getVersion(), AppDatabase.schemaVersion);
      expect(
        await _pragmaValue(database, 'application_id'),
        AppDatabase.applicationId,
      );
      expect(await database.query('legacy_fixture'), [
        {'value': 'preserve-me'},
      ]);
      expect(await database.query('qr_records'), isEmpty);
    },
  );
}

Future<Object?> _pragmaValue(Database database, String pragma) async {
  final row = (await database.rawQuery('PRAGMA $pragma')).single;
  return row.values.single;
}
