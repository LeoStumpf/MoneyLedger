import '../database/daos/expenses_dao.dart';
import '../database/daos/groups_dao.dart';
import '../database/daos/link_dao.dart';
import '../database/daos/members_dao.dart';
import '../matrix/record_crypto.dart';
import 'record_signing.dart';

/// G6: signs [groupId]'s rows that were written while no signer was ready
/// (`pendingSign`, same clock — the signed copy is the same G27 version).
/// Used by the sync engine before every digest / bootstrap, and (G40) when a
/// local-mode ledger is adopted into a Matrix account.
///
/// An expense / payment gets a creation statement (`origin`, "added by") when
/// it is signed for the first time unedited — or, with [originIfMissing],
/// whenever it has none: local-mode records were never signed at all, so
/// their adopting account's device signs their creation too.
///
/// G52: a **link-only** group is skipped — its versions stay unsigned for
/// good (§6.3: link-written versions are never re-signed; a row local mode
/// left `pendingSign` before the group got its link channel included). The
/// policy comes from the DB behind [groups] (`LinkDao.policyOf`).
///
/// Stops quietly once [isAlive] turns false (account switch, G19). Returns
/// the number of rows signed.
Future<int> signPendingRows({
  required RecordCrypto crypto,
  required GroupsDao groups,
  required MembersDao members,
  required ExpensesDao expenses,
  required String groupId,
  required bool Function() isAlive,
  bool originIfMissing = false,
}) async {
  var signed = 0;
  if (await LinkDao(groups.attachedDatabase).isLinkOnly(groupId)) {
    return signed;
  }
  if (!isAlive()) return signed;
  final group = await groups.getGroup(groupId);
  if (!isAlive()) return signed;
  if (group != null && group.pendingSign) {
    await groups.upsertGroupLww(
      groupCompanion(await signGroupMeta(crypto, group)),
    );
    signed++;
  }
  for (final m in await members.getMembers(groupId)) {
    if (!isAlive()) return signed;
    if (m.pendingSign) {
      await members.upsertMemberLww(
        memberCompanion(await signMember(crypto, m)),
      );
      signed++;
    }
  }
  for (final e in await expenses.getAllExpensesForGroup(groupId)) {
    if (!isAlive()) return signed;
    if (e.pendingSign) {
      await expenses.upsertExpenseLww(
        expenseCompanion(
          await signExpense(
            crypto,
            e,
            creating:
                e.origin == null &&
                (originIfMissing || e.updatedAt == e.createdAt),
          ),
        ),
      );
      signed++;
    }
  }
  for (final st in await expenses.getAllSettlementsForGroup(groupId)) {
    if (!isAlive()) return signed;
    if (st.pendingSign) {
      await expenses.upsertSettlementLww(
        settlementCompanion(
          await signSettlement(
            crypto,
            st,
            creating:
                st.origin == null &&
                (originIfMissing || st.updatedAt == st.createdAt),
          ),
        ),
      );
      signed++;
    }
  }
  return signed;
}
