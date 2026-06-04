import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'ledger_transport.dart'
    show groupStateEventType, expenseEventType, settlementEventType;

export 'ledger_transport.dart'
    show groupStateEventType, expenseEventType, settlementEventType;

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

  return Client(
    'MoneyLedger',
    database: db,
    nativeImplementations: NativeImplementations.dummy,
    supportedLoginTypes: {
      AuthenticationTypes.password,
      AuthenticationTypes.sso,
      AuthenticationTypes.token,
    },
    // The SDK only keeps a fixed set of "important" state events available via
    // room.getState() for rooms in the list. Our custom group-metadata event is
    // not in that default set, so without this it gets dropped and a joining
    // user can never read the group — even though the event is in the room.
    importantStateEvents: {groupStateEventType},
  );
}

extension MoneyLedgerMatrix on Client {
  Future<String> createLedgerGroup(String name, String currency) async {
    final roomId = await createRoom(
      name: name,
      preset: CreateRoomPreset.privateChat,
      powerLevelContentOverride: {'events_default': 0},
    );
    final room = getRoomById(roomId);
    if (room != null) {
      await room.client.setRoomStateWithKey(
        roomId,
        groupStateEventType,
        '',
        {'currency': currency},
      );
    }
    return roomId;
  }

  Future<String?> sendExpenseEvent(
    String roomId,
    Map<String, dynamic> content,
  ) async {
    final room = getRoomById(roomId);
    return room?.sendEvent(content, type: expenseEventType);
  }

  Future<String?> sendSettlementEvent(
    String roomId,
    Map<String, dynamic> content,
  ) async {
    final room = getRoomById(roomId);
    return room?.sendEvent(content, type: settlementEventType);
  }

  Future<void> loadRoomHistory(String roomId) async {
    final room = getRoomById(roomId);
    if (room == null) return;
    try {
      while (room.prev_batch != null) {
        await room.requestHistory();
      }
    } catch (_) {
      // Reached beginning of timeline
    }
  }
}
