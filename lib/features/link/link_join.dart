/// G52 step 7: **joining a link group** — the `/join` route, the join page
/// and the native link intake (`docs/design/no-login-sharing.md` §2.2,
/// §6.2, §8.2).
///
/// **How a link arrives.**
/// * Android: an intent filter for `moneyledger://join` and an App Link
///   (`autoVerify`) for `https://leostumpf.github.io/moneyledger/join` —
///   `app_links` delivers it ([joinLinkStreamProvider]) and
///   [JoinLinkListener] opens `/join?<fragment>` (Flutter's own deep
///   linking is off in the manifest: `app_links` is the only reader).
/// * Web: the hash URL strategy turns the link into `#/join?v=1&k=…` —
///   the route reads its query.
/// * Pasted: `/join` without a link shows a paste field (welcome, empty
///   groups list, *Create group*).
///
/// `/join` is never redirected (`routerRedirect`): it works signed out —
/// even before the welcome was seen —, in local mode and on a Matrix
/// account; the page itself waits while the session is still loading.
///
/// **Flow** ([JoinLinkPage]): parse → "Join …?" → first-use disclosure
/// (§9.2) → look-up ([linkJoinLookupProvider]: a one-time fetch from the
/// relays, nothing stored, works without any ledger DB) → refused when this
/// device holds the group as a **non-link** group; with **another link**
/// (G52 step 12: someone reset the invite link) → "Switch to this link?"
/// ([switchLinkGroup]: this device's copy leaves the old link, the channel
/// takes the new secret, "me" stays — no picker) → otherwise
/// "Who are you?" (the group's people, "already used on another phone"
/// hints, *I'm someone new* + name) → join ([linkJoinActionProvider]):
/// 1. signed out (fresh install / no account) → a **local profile** is
///    created with the picked / typed name (welcome counts as seen, §6.2);
/// 2. `LinkSyncEngine.join` stores the channel **before** the first merge,
///    then fetches and merges the group through the record gate's link path;
/// 3. "me" (`link_channels.my_participant_id`) is set — for *someone new*
///    together with the new participant (unsigned, `by` = itself), one
///    transaction — and `currentParticipant` is invalidated; the engine
///    sees "me" and publishes;
/// 4. the group opens.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/link_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/l10n/l10n.dart';
import '../../core/link/link_channel.dart';
import '../../core/link/link_join_probe.dart';
import '../../core/link/link_relay_policy.dart' show parseLinkRelays;
import '../../core/link/link_sync_engine.dart';
import '../../core/link/link_uri.dart';
import '../../core/link/nostr/nostr_relay_pool.dart';
import '../../core/platform/url_helper.dart';
import '../../core/session/app_session.dart';
import '../../core/session/device_prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/action_error.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/large_text.dart';
import '../../models/member_model.dart';
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart';
import 'link_invite.dart';

/// The join route (public, never redirected).
const kJoinLocation = '/join';

/// Whether [uri] is one of our invite links (either form, §2.1) — only the
/// scheme / host / path are looked at; the fragment is parsed by the page.
bool isJoinLink(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  var path = uri.path;
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  return switch (scheme) {
    'https' => host == kLinkWebHost && path == kLinkWebPath,
    kLinkAppScheme => host == kLinkAppHost && path.isEmpty,
    _ => false,
  };
}

/// The route of an opened invite link: `/join?<fragment>` — the secret
/// stays in memory (the router's location), it is never logged.
String joinLocationFor(Uri link) =>
    link.fragment.isEmpty ? kJoinLocation : '$kJoinLocation?${link.fragment}';

// ── look-up + join (seams) ──────────────────────────────────────────────────

/// What the look-up found: the group's [preview] and, when a ledger is
/// open, how this device relates to it.
class LinkJoinLookup {
  final LinkGroupPreview preview;

  /// Why it can't be joined here (null = it can).
  final LinkJoinError? blocker;

  /// This device already joined it as this participant (active) — the page
  /// just opens the group.
  final String? joinedAs;

  const LinkJoinLookup({required this.preview, this.blocker, this.joinedAs});
}

/// The join's look-up: null = nothing found.
typedef LinkJoinLookupFn =
    Future<LinkJoinLookup?> Function(ProviderContainer c, LinkInvite invite);

/// Who the user picked: an existing participant, or someone new.
class LinkJoinRequest {
  final LinkInvite invite;
  final String groupId;

  /// The picked participant (null = someone new, [newName]).
  final String? participantId;

  /// Name of the new participant — and of the local profile when there is
  /// no ledger yet (signed out): the picked person's name then.
  final String name;

  const LinkJoinRequest({
    required this.invite,
    required this.groupId,
    required this.participantId,
    required this.name,
  });
}

/// The join itself; returns the joined group's id.
typedef LinkJoinActionFn =
    Future<String> Function(ProviderContainer c, LinkJoinRequest request);

/// The look-up's wait for the relays (tests shorten it).
final linkJoinFetchTimeoutProvider = Provider<Duration>(
  (ref) => kLinkJoinFetchTimeout,
);

/// Seam: [lookUpLinkGroup] (widget tests replace it).
final linkJoinLookupProvider = Provider<LinkJoinLookupFn>(
  (ref) => lookUpLinkGroup,
);

/// Seam: [joinLinkGroup] (widget tests replace it).
final linkJoinActionProvider = Provider<LinkJoinActionFn>(
  (ref) => joinLinkGroup,
);

/// The switch to a new link of a group shared with another one (G52 step
/// 12); returns the group's id.
typedef LinkSwitchActionFn =
    Future<String> Function(
      ProviderContainer c,
      LinkInvite invite,
      String groupId,
    );

/// Seam: [switchLinkGroup] (widget tests replace it).
final linkSwitchActionProvider = Provider<LinkSwitchActionFn>(
  (ref) => switchLinkGroup,
);

/// The relays a join reads from: the ledger's configured list when one is
/// open, else the defaults.
Future<List<String>> _joinRelays(ProviderContainer c) async {
  if (c.read(ledgerIdentityProvider) == null) return kDefaultLinkRelays;
  final db = c.read(appDatabaseProvider);
  if (db.isSignedOutPlaceholder || db.isClosed) return kDefaultLinkRelays;
  try {
    return parseLinkRelays(
      await SettingsDao(db).linkRelaysRaw(),
      kDefaultLinkRelays,
    );
  } catch (_) {
    return kDefaultLinkRelays;
  }
}

/// The real look-up: [probeLinkGroup] over a short-lived relay pool, then
/// (with a ledger open) [linkJoinBlocker] and "already joined".
Future<LinkJoinLookup?> lookUpLinkGroup(
  ProviderContainer c,
  LinkInvite invite,
) async {
  final clock = c.read(linkClockProvider);
  final pool = NostrRelayPool(
    relays: await _joinRelays(c),
    connector: c.read(linkRelayConnectorProvider),
    verifySignatures: c.read(linkVerifySignaturesProvider),
    nowSeconds: () => clock() ~/ 1000,
  );
  final LinkGroupPreview? preview;
  try {
    preview = await probeLinkGroup(
      invite.secret,
      pool: pool,
      timeout: c.read(linkJoinFetchTimeoutProvider),
    );
  } finally {
    unawaited(pool.close());
  }
  if (preview == null) return null;
  if (c.read(ledgerIdentityProvider) == null) {
    return LinkJoinLookup(preview: preview);
  }
  final db = c.read(appDatabaseProvider);
  if (db.isSignedOutPlaceholder) return LinkJoinLookup(preview: preview);
  final channel = await LinkDao(db).getChannel(preview.groupId);
  final stored =
      channel == null && await GroupsDao(db).getGroup(preview.groupId) != null;
  final blocker = linkJoinBlocker(
    channel: channel,
    groupStored: stored,
    secret: encodeLinkSecret(invite.secret),
  );
  String? joinedAs;
  final me = channel?.myParticipantId;
  if (blocker == null && me != null) {
    final members = await MembersDao(db).getMembers(preview.groupId);
    if (members.any((m) => m.userId == me && m.isActive)) joinedAs = me;
  }
  return LinkJoinLookup(preview: preview, blocker: blocker, joinedAs: joinedAs);
}

/// Nothing usable came from the relays during the join.
class LinkJoinNotFoundException implements Exception {
  const LinkJoinNotFoundException();
  @override
  String toString() => 'LinkJoinNotFoundException';
}

/// The picked participant is no longer an active participant of the group.
class LinkJoinPersonGoneException implements Exception {
  const LinkJoinPersonGoneException();
  @override
  String toString() => 'LinkJoinPersonGoneException';
}

/// The real join — see the library doc (steps 1–3).
Future<String> joinLinkGroup(ProviderContainer c, LinkJoinRequest r) async {
  if (!c.read(linkSyncEnabledProvider)) {
    throw StateError('link sync is off (offline demo)');
  }
  if (c.read(ledgerIdentityProvider) == null) {
    // §6.2: no account and no local profile yet → continue in local mode,
    // named like the picked / new person.
    await c.read(devicePrefsProvider.notifier).startLocalProfile(r.name);
  }
  if (c.read(ledgerIdentityProvider) == null) {
    throw StateError('no ledger to join into');
  }
  final keep = c.listen(linkSyncEngineProvider, (_, _) {});
  try {
    final engine = keep.read();
    final db = c.read(appDatabaseProvider);
    final clock = c.read(linkClockProvider);
    await engine.ready;
    await engine.join(
      r.groupId,
      encodeLinkSecret(r.invite.secret),
      timeout: c.read(linkJoinFetchTimeoutProvider),
    );
    final link = LinkDao(db);
    if (await GroupsDao(db).getGroup(r.groupId) == null) {
      // Gone from the relays since the look-up: don't keep a channel of a
      // group this device doesn't have.
      await link.deleteChannel(r.groupId);
      throw const LinkJoinNotFoundException();
    }
    await chooseLinkParticipant(
      db,
      r.groupId,
      participantId: r.participantId,
      newName: r.name,
      clock: clock,
    );
    c.invalidate(currentParticipantProvider(r.groupId));
    c.invalidate(linkInviteStateProvider(r.groupId));
    return r.groupId;
  } finally {
    keep.close();
  }
}

/// G52 step 12: this device shares [groupId] with another link and the
/// user chose to switch to [invite] (someone reset the invite link) —
/// `LinkSyncEngine.switchLink`: our copy leaves the old link (bounded),
/// the channel takes the new secret with the next epoch and a fresh Nostr
/// key, "me" stays, then the new link's snapshots are fetched and merged.
Future<String> switchLinkGroup(
  ProviderContainer c,
  LinkInvite invite,
  String groupId,
) async {
  if (!c.read(linkSyncEnabledProvider)) {
    throw StateError('link sync is off (offline demo)');
  }
  final keep = c.listen(linkSyncEngineProvider, (_, _) {});
  try {
    final engine = keep.read();
    await engine.ready;
    await engine.switchLink(
      groupId,
      encodeLinkSecret(invite.secret),
      timeout: c.read(linkJoinFetchTimeoutProvider),
    );
    c.invalidate(currentParticipantProvider(groupId));
    c.invalidate(linkInviteStateProvider(groupId));
    return groupId;
  } finally {
    keep.close();
  }
}

/// "Who am I" in link group [groupId] (§6.1/§6.2) — the join picker's
/// confirm and (G52 step 10) the group page's picker after a restore
/// re-opened the channel without "me". One transaction: [participantId] (an
/// active participant) becomes `my_participant_id`, else someone new named
/// [newName] — "me" first, so the new participant is written as a link
/// version by itself (unsigned, not `pendingSign`, `by` = itself). Throws
/// [LinkJoinPersonGoneException] when the picked person is gone. The caller
/// invalidates `currentParticipantProvider` (+ the invite state).
Future<void> chooseLinkParticipant(
  AppDatabase db,
  String groupId, {
  String? participantId,
  required String newName,
  required int Function() clock,
}) {
  final link = LinkDao(db);
  final members = MembersDao(db);
  return db.transaction(() async {
    if (participantId != null) {
      final people = await members.getMembers(groupId);
      if (!people.any((m) => m.userId == participantId && m.isActive)) {
        throw const LinkJoinPersonGoneException();
      }
      await link.setMyParticipant(groupId, participantId);
    } else {
      final id = const Uuid().v7();
      await link.setMyParticipant(groupId, id);
      await members.upsertMemberLww(
        memberCompanion(
          MemberModel(
            groupId: groupId,
            userId: id,
            displayName: newName.trim(),
            status: 'active',
            updatedAt: clock(),
            linkAuthor: id,
          ),
        ),
      );
    }
  });
}

// ── native link intake ──────────────────────────────────────────────────────

/// One opened invite link. Identity equality on purpose: Riverpod drops a
/// provider update equal to the previous one, so opening the **same** link
/// again (cancelled join, tapped once more in the chat) must still be a new
/// event.
class JoinLinkEvent {
  JoinLinkEvent(this.uri);
  final Uri uri;
}

/// Invite links opened on this device (Android intent / App Link; empty on
/// the web, where the route carries them). Overridden with an empty stream
/// in widget tests and the offline demo.
final joinLinkStreamProvider = StreamProvider<JoinLinkEvent>(
  (ref) => incomingAppLinks().where(isJoinLink).map(JoinLinkEvent.new),
);

/// Opens `/join` for every invite link [joinLinkStreamProvider] delivers.
class JoinLinkListener extends ConsumerWidget {
  const JoinLinkListener({super.key, required this.go, required this.child});

  /// Navigates (the app's router).
  final void Function(String location) go;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(joinLinkStreamProvider, (_, next) {
      final event = next.value;
      if (event != null) go(joinLocationFor(event.uri));
    });
    return child;
  }
}

// ── the page ────────────────────────────────────────────────────────────────

enum _Step {
  paste,
  invalid,
  intro,
  searching,
  notFound,
  blocked,
  switchLink,
  pick,
  busy,
}

/// `/join`: see the library doc. [fragment] is the link's fragment
/// (`v=1&k=…&n=…`); null / empty → the paste field.
class JoinLinkPage extends ConsumerStatefulWidget {
  const JoinLinkPage({super.key, this.fragment});

  final String? fragment;

  @override
  ConsumerState<JoinLinkPage> createState() => _JoinLinkPageState();
}

class _JoinLinkPageState extends ConsumerState<JoinLinkPage> {
  final _paste = TextEditingController();
  final _name = TextEditingController();
  String? _pasteError;
  String? _nameError;

  late _Step _step;
  LinkInvite? _invite;
  LinkUriException? _linkError;
  LinkJoinLookup? _lookup;

  /// The picked participant id; [_newPerson] = "someone new".
  String? _picked;
  bool _newPerson = false;

  /// The switch to a new link (step 12) is running.
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    final f = widget.fragment;
    if (f == null || f.isEmpty) {
      _step = _Step.paste;
    } else {
      _accept(() => parseLinkFragment(f));
    }
    final profile = ref.read(localProfileProvider);
    if (profile != null) _name.text = profile.name;
  }

  @override
  void dispose() {
    _paste.dispose();
    _name.dispose();
    super.dispose();
  }

  void _accept(LinkInvite Function() parse) {
    try {
      _invite = parse();
      _linkError = null;
      _step = _Step.intro;
    } on LinkUriException catch (e) {
      _linkError = e;
      _step = _Step.invalid;
    }
  }

  void _submitPaste() {
    final text = _paste.text.trim();
    if (text.isEmpty) return;
    try {
      final invite = parseLinkUri(text);
      setState(() {
        _pasteError = null;
        _accept(() => invite);
      });
    } on LinkUriException catch (e) {
      setState(() => _pasteError = _linkErrorText(context.l10n, e));
    }
  }

  String _linkErrorText(AppLocalizations l, LinkUriException e) =>
      e.kind == LinkUriError.unsupportedVersion
      ? l.joinLinkUpdateApp
      : l.joinLinkInvalidBody;

  Future<void> _start() async {
    if (!await ensureLinkDisclosure(context, ref)) return;
    await _search();
  }

  Future<void> _search() async {
    final invite = _invite;
    if (invite == null || !mounted) return;
    final errors = ActionErrors.of(context);
    final lookUp = ref.read(linkJoinLookupProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _step = _Step.searching);
    final LinkJoinLookup? found;
    try {
      found = await lookUp(container, invite);
    } catch (e) {
      if (!mounted) return;
      errors.show(e, retry: _search);
      setState(() => _step = _Step.intro);
      return;
    }
    if (!mounted) return;
    if (found == null) {
      setState(() => _step = _Step.notFound);
      return;
    }
    final joined = found.joinedAs;
    if (joined != null) {
      context.go('/groups/${found.preview.groupId}/expenses');
      return;
    }
    // G52 step 12 follow-up: only "this link was replaced" markers — the
    // group moved to a new link.
    if (found.preview.onlyReplaced) {
      setState(() {
        _lookup = found;
        _step = _Step.notFound;
      });
      return;
    }
    setState(() {
      _lookup = found;
      _step = switch (found!.blocker) {
        null => _Step.pick,
        LinkJoinError.otherLink => _Step.switchLink,
        _ => _Step.blocked,
      };
      if (_picked != null &&
          !found.preview.people.any((p) => p.id == _picked)) {
        _picked = null;
      }
      if (found.preview.people.isEmpty) _newPerson = true;
    });
  }

  Future<void> _join() async {
    final lookup = _lookup;
    final invite = _invite;
    if (lookup == null || invite == null) return;
    final l = context.l10n;
    final String name;
    final String? participant;
    if (_newPerson) {
      name = _name.text.trim();
      if (name.isEmpty) {
        setState(() => _nameError = l.localSetupNameRequired);
        return;
      }
      participant = null;
    } else {
      final p = lookup.preview.people.where((p) => p.id == _picked).firstOrNull;
      if (p == null) return;
      name = p.name;
      participant = p.id;
    }
    final errors = ActionErrors.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final action = ref.read(linkJoinActionProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _nameError = null;
      _step = _Step.busy;
    });
    try {
      final groupId = await action(
        container,
        LinkJoinRequest(
          invite: invite,
          groupId: lookup.preview.groupId,
          participantId: participant,
          name: name,
        ),
      );
      if (!mounted) return;
      context.go('/groups/$groupId/expenses');
    } on LinkJoinNotFoundException {
      if (mounted) setState(() => _step = _Step.notFound);
    } on LinkJoinPersonGoneException {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l.joinLinkPersonGone)));
      _picked = null;
      await _search();
    } on LinkJoinException catch (e) {
      if (!mounted) return;
      setState(() {
        _lookup = LinkJoinLookup(preview: lookup.preview, blocker: e.kind);
        _step = e.kind == LinkJoinError.otherLink
            ? _Step.switchLink
            : _Step.blocked;
      });
    } catch (e) {
      if (!mounted) return;
      errors.show(e);
      setState(() => _step = _Step.pick);
    }
  }

  /// G52 step 12: switch this device's copy of the group to the new link.
  Future<void> _switch() async {
    final lookup = _lookup;
    final invite = _invite;
    if (lookup == null || invite == null) return;
    final errors = ActionErrors.of(context);
    final action = ref.read(linkSwitchActionProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _switching = true);
    try {
      final groupId = await action(container, invite, lookup.preview.groupId);
      if (!mounted) return;
      context.go('/groups/$groupId/expenses');
    } catch (e) {
      if (!mounted) return;
      errors.show(e);
      setState(() => _switching = false);
    }
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/groups');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = ref.watch(appSessionProvider);
    final loading = session == AppSessionKind.loading;
    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(
          key: const Key('joinLinkClose'),
          onPressed: _leave,
        ),
        title: AppBarTitle(l.joinLinkTitle),
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : _body(context, l, session),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l, AppSessionKind s) {
    switch (_step) {
      case _Step.paste:
        return _paged(
          key: const Key('joinLinkPaste'),
          children: [
            Text(l.joinLinkPasteHint),
            const SizedBox(height: Insets.l),
            TextField(
              key: const Key('joinLinkPasteField'),
              controller: _paste,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submitPaste(),
              decoration: InputDecoration(
                labelText: l.joinLinkPasteLabel,
                errorText: _pasteError,
                errorMaxLines: 3,
                prefixIcon: const Icon(Icons.link),
              ),
            ),
            const SizedBox(height: Insets.xl),
            FilledButton(
              key: const Key('joinLinkPasteContinue'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _submitPaste,
              child: Text(l.joinLinkContinue),
            ),
          ],
        );
      case _Step.invalid:
        return EmptyState(
          key: const Key('joinLinkInvalid'),
          icon: Icons.link_off,
          title: l.joinLinkInvalidTitle,
          body: _linkErrorText(l, _linkError!),
          actions: [
            OutlinedButton(
              key: const Key('joinLinkPasteInstead'),
              onPressed: () => setState(() => _step = _Step.paste),
              child: Text(l.joinLinkPasteLabel),
            ),
          ],
        );
      case _Step.intro:
        final name = _invite?.name;
        return _paged(
          key: const Key('joinLinkIntro'),
          children: [
            const Center(child: Icon(Icons.group_add_outlined, size: 64)),
            const SizedBox(height: Insets.l),
            Text(
              name == null ? l.joinLinkInvited : l.joinLinkInvitedTo(name),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.m),
            Text(l.joinLinkIntroBody, textAlign: TextAlign.center),
            if (s == AppSessionKind.signedOut) ...[
              const SizedBox(height: Insets.m),
              Text(
                l.joinLinkNoAccountHint,
                key: const Key('joinLinkNoAccountHint'),
                textAlign: TextAlign.center,
                style: _muted(context),
              ),
            ],
            const SizedBox(height: Insets.xl),
            FilledButton(
              key: const Key('joinLinkStart'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _start,
              child: Text(l.join),
            ),
          ],
        );
      case _Step.searching:
        return EmptyState(
          key: const Key('joinLinkSearching'),
          icon: Icons.travel_explore,
          busy: true,
          title: l.joinLinkSearching,
        );
      case _Step.notFound:
        final replaced = _lookup?.preview.onlyReplaced ?? false;
        return EmptyState(
          key: Key(replaced ? 'joinLinkReplaced' : 'joinLinkNotFound'),
          icon: replaced ? Icons.link_off : Icons.cloud_off_outlined,
          title: replaced ? l.joinLinkReplacedTitle : l.joinLinkNotFoundTitle,
          body: replaced ? l.joinLinkReplacedBody : l.joinLinkNotFoundBody,
          actions: [
            FilledButton(
              key: const Key('joinLinkRetry'),
              onPressed: _search,
              child: Text(l.joinLinkRetry),
            ),
          ],
        );
      case _Step.blocked:
        return EmptyState(
          key: const Key('joinLinkBlocked'),
          icon: Icons.block,
          title: l.joinLinkBlockedTitle,
          body: switch (_lookup?.blocker) {
            LinkJoinError.otherLink => l.joinLinkOtherLink,
            _ => l.joinLinkNotALinkGroup,
          },
        );
      case _Step.switchLink:
        final groupName = _lookup?.preview.name ?? _invite?.name;
        return _paged(
          key: const Key('joinLinkSwitch'),
          children: [
            const Center(child: Icon(Icons.autorenew, size: 64)),
            const SizedBox(height: Insets.l),
            Semantics(
              header: true,
              child: Text(
                groupName == null
                    ? l.joinLinkSwitchTitleNoName
                    : l.joinLinkSwitchTitle(groupName),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: Insets.m),
            Text(l.joinLinkSwitchBody, textAlign: TextAlign.center),
            const SizedBox(height: Insets.m),
            Text(
              l.joinLinkSwitchCaution,
              textAlign: TextAlign.center,
              style: _muted(context),
            ),
            if (_lookup?.preview.replaced ?? false) ...[
              const SizedBox(height: Insets.m),
              Text(
                l.joinLinkSwitchReplaced,
                key: const Key('joinLinkSwitchReplaced'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: Insets.xl),
            FilledButton(
              key: const Key('joinLinkSwitchConfirm'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _switching ? null : _switch,
              child: _switching
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.joinLinkSwitchConfirm),
            ),
            const SizedBox(height: Insets.s),
            TextButton(
              key: const Key('joinLinkSwitchCancel'),
              onPressed: _switching ? null : _leave,
              child: Text(l.joinLinkSwitchKeep),
            ),
          ],
        );
      case _Step.pick:
      case _Step.busy:
        return _picker(context, l);
    }
  }

  TextStyle? _muted(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  Widget _paged({required Key key, required List<Widget> children}) =>
      SingleChildScrollView(
        key: key,
        padding: const EdgeInsets.all(Insets.xl),
        child: ContentWidth(
          maxWidth: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );

  Widget _picker(BuildContext context, AppLocalizations l) {
    final preview = _lookup!.preview;
    final busy = _step == _Step.busy;
    final theme = Theme.of(context);
    final groupName = preview.name ?? _invite?.name;
    final duplicate = _newPerson
        ? duplicateNameOf(_name.text, preview.people.map((p) => p.name))
        : null;
    final canJoin =
        !busy && (_newPerson ? _name.text.trim().isNotEmpty : _picked != null);
    Widget option({
      required Key key,
      required bool selected,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
    }) => ListTile(
      key: key,
      enabled: !busy,
      selected: selected,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: onTap,
    );
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const Key('joinLinkPicker'),
            padding: const EdgeInsets.symmetric(vertical: Insets.l),
            child: ContentWidth(
              maxWidth: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
                    child: Semantics(
                      header: true,
                      child: Text(
                        groupName == null
                            ? l.whichParticipantAreYou
                            : l.joinLinkPickTitle(groupName),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                  if (preview.replaced)
                    Padding(
                      key: const Key('joinLinkPickReplaced'),
                      padding: const EdgeInsets.fromLTRB(
                        Insets.xl,
                        Insets.m,
                        Insets.xl,
                        0,
                      ),
                      child: Text(
                        l.joinLinkPickReplaced,
                        style: _muted(context),
                      ),
                    ),
                  const SizedBox(height: Insets.m),
                  for (final p in preview.people)
                    option(
                      key: Key('joinLinkPerson-${p.id}'),
                      selected: !_newPerson && _picked == p.id,
                      title: p.name,
                      subtitle: p.usedElsewhere
                          ? l.joinLinkUsedElsewhere
                          : null,
                      onTap: () => setState(() {
                        _picked = p.id;
                        _newPerson = false;
                      }),
                    ),
                  option(
                    key: const Key('joinLinkNewPerson'),
                    selected: _newPerson,
                    title: l.imSomeoneNew,
                    onTap: () => setState(() => _newPerson = true),
                  ),
                  if (_newPerson)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.xl,
                        Insets.s,
                        Insets.xl,
                        0,
                      ),
                      child: TextField(
                        key: const Key('joinLinkNameField'),
                        controller: _name,
                        enabled: !busy,
                        autofocus: preview.people.isEmpty,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() => _nameError = null),
                        onSubmitted: (_) => _join(),
                        decoration: InputDecoration(
                          labelText: l.yourName,
                          errorText: _nameError,
                          helperText: duplicate == null
                              ? null
                              : l.duplicatePersonHint(duplicate),
                          helperMaxLines: 4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Insets.page),
          child: ContentWidth(
            maxWidth: 520,
            child: FilledButton(
              key: const Key('joinLinkConfirm'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: canJoin ? _join : null,
              child: busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.join),
            ),
          ),
        ),
      ],
    );
  }
}
