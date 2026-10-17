import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqlite_ffi;

class AppDatabase {
  AppDatabase({required this.factory, required this.path});

  static const schemaVersion = 2;

  // ASCII "QROP", used by SQLite to identify a database owned by QR Ops.
  static const applicationId = 0x51524F50;

  final DatabaseFactory factory;
  final String path;

  static Future<Database> openDefault() async {
    late final DatabaseFactory factory;
    late final String databasePath;

    if (Platform.isWindows) {
      sqlite_ffi.sqfliteFfiInit();
      factory = sqlite_ffi.databaseFactoryFfi;
      final supportDirectory = Platform.environment['LOCALAPPDATA'];
      if (supportDirectory == null || supportDirectory.isEmpty) {
        throw StateError(
          'A pasta de dados local do usuário não está definida.',
        );
      }
      final databaseDirectory = Directory(
        '$supportDirectory${Platform.pathSeparator}QR Ops',
      );
      await databaseDirectory.create(recursive: true);
      databasePath =
          '${databaseDirectory.path}${Platform.pathSeparator}qr_ops.db';
    } else if (Platform.isAndroid) {
      factory = databaseFactory;
      final directory = await getDatabasesPath();
      databasePath = '$directory${Platform.pathSeparator}qr_ops.db';
    } else {
      throw UnsupportedError(
        'O QR Ops está configurado para Android e Windows.',
      );
    }

    return AppDatabase(factory: factory, path: databasePath).open();
  }

  Future<Database> open() {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) => _migrate(database, 0, version),
        onUpgrade: _migrate,
      ),
    );
  }

  Future<void> _migrate(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      switch (version) {
        case 1:
          await database.execute('PRAGMA application_id = $applicationId');
        case 2:
          await database.execute('''
            CREATE TABLE qr_records (
              id TEXT PRIMARY KEY NOT NULL,
              operation_type TEXT NOT NULL
                CHECK (operation_type IN ('create', 'read')),
              symbology TEXT NOT NULL,
              content_type TEXT NOT NULL,
              content TEXT NOT NULL,
              created_at_ms INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE INDEX qr_records_created_at_idx
            ON qr_records (created_at_ms DESC, id DESC)
          ''');
        default:
          throw StateError('Migração SQLite ausente para a versão $version.');
      }
    }
  }
}
