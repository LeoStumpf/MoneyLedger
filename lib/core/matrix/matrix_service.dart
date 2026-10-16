import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:matrix/encryption.dart' show KeyVerificationMethod;
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'request_timeout_http_client.dart';
import 'sync_filter.dart';

/// [httpClient]: the HTTP client to use (G18 review 2: the background round
/// passes its own, so it can abort requests in flight before it closes the
/// stores); default a fresh [RequestTimeoutHttpClient].
Future<Client> buildMatrixClient({http.Client? httpClient}) async {
  // G44: the SDK logs via `print` (not debugPrint), level info by default —
  // request URLs, user ids, device ids. Release builds keep only `wtf`
  // (there is no "off" level; those few are crash-class errors).
  if (kReleaseMode) Logs().level = Level.wtf;
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

  // G45: which stored sync filter id is the minimal one (see sync_filter.dart).
  String? marked;
  try {
    final accountData = await db.getAccountData();
    marked = markedSyncFilterId(accountData[kSyncFilterMarkerType]?.content);
    final stored = (await db.getClient('MoneyLedger'))?['sync_filter_id'];
    if (syncCacheFromOtherFilter(
      stored: stored is String ? stored : null,
      marked: marked,
    )) {
      // Rooms / presence / account data synced with the SDK's default
      // filter (pre-G45): drop them once; the session and keys stay.
      await db.clearCache();
      Logs().i('[g45] cleared sync data of the previous sync filter');
    }
  } catch (e) {
    // Unreadable → null → the minimal filter is defined again (harmless).
    Logs().w('[g45] checking the sync filter marker failed: $e');
  }

  // Phase B is roomless: groups/membership live in the local DB and replicate
  // via encrypted to-device messages, so there are no room state events to keep.
  final client = MoneyLedgerClient(
    'MoneyLedger',
    markedSyncFilterId: marked,
    database: db,
    // G36: bound every request's wait for response headers — a request on a
    // socket that died in a network switch otherwise hangs the sync loop.
    httpClient: httpClient ?? RequestTimeoutHttpClient(http.Client()),
    nativeImplementations: NativeImplementations.dummy,
    // SAS (emoji) device verification over to-device messages (Phase F /
    // G11). Without these the SDK ignores every verification request and
    // advertises no method when starting one.
    verificationMethods: {
      KeyVerificationMethod.emoji,
      KeyVerificationMethod.numbers,
    },
    supportedLoginTypes: {
      AuthenticationTypes.password,
      AuthenticationTypes.sso,
      AuthenticationTypes.token,
    },
    // G45: no rooms, presence or account data — only to-device, device lists
    // and one-time-key counts (not filterable) reach the app.
    syncFilter: Filter.fromJson(minimalSyncFilterJson()),
  );
  // G45: polling `/sync` never marks the user online (`set_presence`).
  client.syncPresence = PresenceType.values.firstWhere(
    (p) => p.name == kSyncPresence,
  );
  return client;
}

/// The SDK client with the G45 sync-filter refresh: the SDK defines its sync
/// filter once and keeps the id forever (installs from before G45 hold the
/// id of its default filter). [syncFilterId] hides a stored id that isn't
/// recorded as the minimal filter's, so the SDK's `_checkSyncFilter` defines
/// [syncFilter] again before the next `/sync` (and stores the new id);
/// [defineFilter] records the new id in a device-local marker.
class MoneyLedgerClient extends Client {
  MoneyLedgerClient(
    super.clientName, {
    required super.database,
    required this.markedSyncFilterId,
    super.httpClient,
    super.nativeImplementations,
    super.verificationMethods,
    super.supportedLoginTypes,
    super.syncFilter,
  });

  /// The filter id recorded as the minimal filter's (null = none yet).
  String? markedSyncFilterId;

  @override
  String? get syncFilterId => effectiveSyncFilterId(
    stored: super.syncFilterId,
    marked: markedSyncFilterId,
  );

  @override
  Future<String> defineFilter(String userId, Filter body) async {
    final id = await super.defineFilter(userId, body);
    if (identical(body, syncFilter)) {
      markedSyncFilterId = id;
      try {
        await database.storeAccountData(
          kSyncFilterMarkerType,
          syncFilterMarker(id),
        );
      } catch (e) {
        // Not recorded → defined again on the next start (harmless).
        Logs().w('[g45] storing the sync filter marker failed: $e');
      }
    }
    return id;
  }
}
