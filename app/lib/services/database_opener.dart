import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openHomeScatoloDatabase({
  required String dbName,
  required int version,
  required OnDatabaseCreateFn onCreate,
}) async {
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    final DatabaseFactory databaseFactory = databaseFactoryFfi;
    return databaseFactory.openDatabase(
      dbName,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: onCreate,
      ),
    );
  }

  final String databasesPath = await getDatabasesPath();
  final String databasePath = path.join(databasesPath, dbName);

  return openDatabase(
    databasePath,
    version: version,
    onCreate: onCreate,
  );
}
