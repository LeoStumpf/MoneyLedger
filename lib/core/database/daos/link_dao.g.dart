// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'link_dao.dart';

// ignore_for_file: type=lint
mixin _$LinkDaoMixin on DatabaseAccessor<AppDatabase> {
  $LinkChannelsTable get linkChannels => attachedDatabase.linkChannels;
  $LinkPeersTable get linkPeers => attachedDatabase.linkPeers;
  LinkDaoManager get managers => LinkDaoManager(this);
}

class LinkDaoManager {
  final _$LinkDaoMixin _db;
  LinkDaoManager(this._db);
  $$LinkChannelsTableTableManager get linkChannels =>
      $$LinkChannelsTableTableManager(_db.attachedDatabase, _db.linkChannels);
  $$LinkPeersTableTableManager get linkPeers =>
      $$LinkPeersTableTableManager(_db.attachedDatabase, _db.linkPeers);
}
