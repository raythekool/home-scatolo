import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<Database> openHomeScatoloDatabase({
  required String dbName,
  required int version,
  required OnDatabaseCreateFn onCreate,
}) {
  return databaseFactoryFfiWeb.openDatabase(
    dbName,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: onCreate,
    ),
  );
}
