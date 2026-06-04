import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

Future<Client> buildMatrixClient() async {
  MatrixSdkDatabase db;

  if (kIsWeb) {
    // On web, MatrixSdkDatabase uses IndexedDB by default (no sqfliteFactory).
    db = await MatrixSdkDatabase.init('money_ledger_matrix');
  } else {
    final appDir = await getApplicationSupportDirectory();
    // matrix 7.x's BoxCollection requires an already-OPENED sqflite Database on
    // native — passing only sqfliteFactory throws "You must provide a Database
    // `sqfliteDatabase` for use on native" (sqflite_box.dart). The factory is
    // used only for high-level ops like delete. So open the DB here and pass it.
    final database = await sqflite.openDatabase(
      '${appDir.path}/money_ledger_matrix.sqlite',
    );
    db = await MatrixSdkDatabase.init(
      'money_ledger_matrix',
      database: database,
      sqfliteFactory: sqflite.databaseFactory,
      fileStorageLocation: appDir.uri,
    );
  }

  // Phase B is roomless: groups/membership live in the local DB and replicate
  // via encrypted to-device messages, so there are no room state events to keep.
  return Client(
    'MoneyLedger',
    database: db,
    nativeImplementations: NativeImplementations.dummy,
    supportedLoginTypes: {
      AuthenticationTypes.password,
      AuthenticationTypes.sso,
      AuthenticationTypes.token,
    },
  );
}
