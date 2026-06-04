import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../expenses/expenses_provider.dart';

part 'group_provider.g.dart';

@riverpod
Stream<List<GroupModel>> ledgerGroups(Ref ref) {
  return ref.watch(groupsDaoProvider).watchAllGroups();
}

@riverpod
Stream<List<MemberModel>> groupMembers(Ref ref, String groupId) {
  return ref.watch(membersDaoProvider).watchMembers(groupId);
}

/// This device's own Matrix ID (empty until the transport/client is ready).
@riverpod
String currentUserId(Ref ref) =>
    ref.watch(ledgerTransportProvider).value?.userId ?? '';

@riverpod
class GroupCreator extends _$GroupCreator {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Creates a group locally (roomless): a fresh UUID id, with the creator as
  /// the first active member. Nothing is sent to Matrix — members are added (and
  /// the group replicated to them) via [MemberAdder].
  Future<void> create(String name, String currency) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final groupId = const Uuid().v7();
      final me = (await ref.read(ledgerTransportProvider.future)).userId;
      await ref.read(groupsDaoProvider).upsertGroup(GroupsCompanion(
            roomId: Value(groupId),
            name: Value(name),
            currency: Value(currency),
          ));
      await ref.read(membersDaoProvider).upsertMemberLww(MembersCompanion(
            groupId: Value(groupId),
            userId: Value(me),
            status: const Value('active'),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ));
    });
  }
}

@riverpod
class MemberAdder extends _$MemberAdder {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Adds [userId] (a Matrix ID) to the group: records them locally, sends them
  /// the whole group as a bootstrap payload ("send my friend the database"), and
  /// notifies existing members of the new member.
  Future<void> add(String groupId, String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final memberDao = ref.read(membersDaoProvider);
      await memberDao.upsertMemberLww(MembersCompanion(
        groupId: Value(groupId),
        userId: Value(userId),
        status: const Value('active'),
        updatedAt: Value(now),
      ));

      final transport = await ref.read(ledgerTransportProvider.future);

      // 1) Bootstrap the new member with the full group state + ledger.
      await transport.sendToUsers(
          {userId}, bootstrapEventType, await _buildBootstrap(groupId));

      // 2) Tell the existing active members about the new member.
      final others = (await memberDao.activeMemberIds(groupId))
          .where((m) => m != userId)
          .toSet();
      await transport.sendToUsers(others, memberEventType, {
        'group': groupId,
        'user': userId,
        'status': 'active',
        'updated_at': now,
      });
    });
  }

  Future<Map<String, dynamic>> _buildBootstrap(String groupId) async {
    final group = await ref.read(groupsDaoProvider).getGroup(groupId);
    final members = await ref.read(membersDaoProvider).getMembers(groupId);
    final expenses =
        await ref.read(expensesDaoProvider).getExpensesForRoom(groupId);
    final settlements =
        await ref.read(expensesDaoProvider).getSettlementsForRoom(groupId);
    return {
      'group': groupId,
      'name': group?.name ?? groupId,
      'currency': group?.currency ?? 'EUR',
      'members': members
          .map((m) => {
                'group': groupId,
                'user': m.userId,
                'status': m.status,
                'updated_at': m.updatedAt,
              })
          .toList(),
      'expenses': expenses
          .map((e) => {
                'group': groupId,
                'id': e.id,
                'description': e.description,
                'amount': e.amountCents,
                'currency': e.currency,
                'paid_by': e.paidBy,
                'split': jsonDecode(e.splitsJson),
                'created_at': e.createdAt,
              })
          .toList(),
      'settlements': settlements
          .map((s) => {
                'group': groupId,
                'id': s.id,
                'amount': s.amountCents,
                'currency': s.currency,
                'from': s.fromUser,
                'to': s.toUser,
                'created_at': s.createdAt,
              })
          .toList(),
    };
  }
}

@riverpod
class MemberRemover extends _$MemberRemover {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Marks [userId] removed (last-writer-wins) and relays the change. Their
  /// expense history stays in Drift, so balances are preserved — only their
  /// membership status changes. The removed user is included in the relay so
  /// their own device updates too.
  Future<void> remove(String groupId, String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final memberDao = ref.read(membersDaoProvider);
      await memberDao.upsertMemberLww(MembersCompanion(
        groupId: Value(groupId),
        userId: Value(userId),
        status: const Value('removed'),
        updatedAt: Value(now),
      ));
      final targets =
          (await memberDao.getMembers(groupId)).map((m) => m.userId).toSet();
      final transport = await ref.read(ledgerTransportProvider.future);
      await transport.sendToUsers(targets, memberEventType, {
        'group': groupId,
        'user': userId,
        'status': 'removed',
        'updated_at': now,
      });
    });
  }
}
