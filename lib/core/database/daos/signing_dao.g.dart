// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signing_dao.dart';

// ignore_for_file: type=lint
mixin _$SigningDaoMixin on DatabaseAccessor<AppDatabase> {
  $KnownDeviceKeysTable get knownDeviceKeys => attachedDatabase.knownDeviceKeys;
  $RejectedVersionsTable get rejectedVersions =>
      attachedDatabase.rejectedVersions;
  SigningDaoManager get managers => SigningDaoManager(this);
}

class SigningDaoManager {
  final _$SigningDaoMixin _db;
  SigningDaoManager(this._db);
  $$KnownDeviceKeysTableTableManager get knownDeviceKeys =>
      $$KnownDeviceKeysTableTableManager(
        _db.attachedDatabase,
        _db.knownDeviceKeys,
      );
  $$RejectedVersionsTableTableManager get rejectedVersions =>
      $$RejectedVersionsTableTableManager(
        _db.attachedDatabase,
        _db.rejectedVersions,
      );
}
