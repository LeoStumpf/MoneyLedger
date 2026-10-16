// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_dao.dart';

// ignore_for_file: type=lint
mixin _$HistoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $RecordHistoryTable get recordHistory => attachedDatabase.recordHistory;
  $AppSettingsTable get appSettings => attachedDatabase.appSettings;
  HistoryDaoManager get managers => HistoryDaoManager(this);
}

class HistoryDaoManager {
  final _$HistoryDaoMixin _db;
  HistoryDaoManager(this._db);
  $$RecordHistoryTableTableManager get recordHistory =>
      $$RecordHistoryTableTableManager(_db.attachedDatabase, _db.recordHistory);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db.attachedDatabase, _db.appSettings);
}
