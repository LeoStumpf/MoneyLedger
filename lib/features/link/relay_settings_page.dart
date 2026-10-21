/// G52 step 9: **Settings → Relays** — the Nostr relays this device's link
/// groups sync through (design doc §4.6, §9.2, §9.4): each relay's status
/// (accepted our last update / refuses our updates / rate-limited / needs
/// an account …) and terms link, *Add relay…* (NIP-11 check first: a relay
/// needing an account or without NIP-40 is refused; one that doesn't
/// answer can be added anyway), remove, *Use the default relays*.
///
/// Opening the page contacts nobody (G43): the list and states come from
/// the ledger DB via the link sync engine; only *Add relay…* fetches the
/// new relay's NIP-11 document (a user action). The list is per ledger
/// (account / local mode), device-local, never synced — the invite link
/// names no relays (§14 Q3), the page says so.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n.dart';
import '../../core/link/link_sync_engine.dart';
import '../../core/link/nostr/nip11.dart';
import '../../core/link/nostr/nostr_relay_pool.dart' show kDefaultLinkRelays;
import '../../core/theme/app_theme.dart';
import '../../core/widgets/action_error.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/large_text.dart';
import 'relay_settings.dart';

/// Route of the relay settings page.
const kRelaySettingsLocation = '/settings/relays';

typedef LinkRelaysSetter =
    Future<void> Function(List<String> relays, {Map<String, RelayInfo> info});

/// The page's seam to `LinkSyncEngine.setRelays` (widget tests replace it).
final linkRelaysSetterProvider = Provider<LinkRelaysSetter>(
  (ref) =>
      (relays, {info = const {}}) =>
          ref.read(linkSyncEngineProvider).setRelays(relays, info: info),
);

/// The clock of the status lines (tests pin it).
final relaySettingsClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class RelaySettingsPage extends ConsumerWidget {
  const RelaySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final relaysAsync = ref.watch(linkRelaysViewProvider);
    final relays = relaysAsync.value;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget para(String text, {Key? key}) => Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.page,
        Insets.s,
        Insets.page,
        Insets.s,
      ),
      child: Text(text, key: key, style: muted),
    );
    final urls = [for (final r in relays ?? const <LinkRelayView>[]) r.url];
    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l.relaysTitle)),
      body: ContentWidth(
        child: ListView(
          key: const Key('relaySettingsList'),
          padding: EdgeInsets.only(
            bottom: Insets.xl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            para(l.relaysIntro),
            if (urls.any(kDefaultLinkRelays.contains))
              para(l.relaysOneOperator, key: const Key('relaysOneOperator')),
            para(l.relaysCommon),
            if (relays == null)
              const Padding(
                padding: EdgeInsets.all(Insets.l),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final r in relays)
                _RelayTile(relay: r, canRemove: relays.length > 1, all: urls),
            const SizedBox(height: Insets.s),
            if (relays != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.page),
                child: Wrap(
                  spacing: Insets.s,
                  runSpacing: Insets.s,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('relayAdd'),
                      onPressed: () => _addRelay(context, ref, urls),
                      icon: const Icon(Icons.add),
                      label: Text(l.relayAdd),
                    ),
                    if (!isDefaultRelayList(urls))
                      TextButton(
                        key: const Key('relaysRestoreDefaults'),
                        onPressed: () => _restoreDefaults(context, ref),
                        child: Text(l.relaysRestoreDefaults),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _addRelay(
  BuildContext context,
  WidgetRef ref,
  List<String> current,
) async {
  final l = context.l10n;
  final errors = ActionErrors.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final setter = ref.read(linkRelaysSetterProvider);
  final fetcher = ref.read(linkRelayInfoFetcherProvider);
  final added = await showDialog<({String url, RelayInfo? info})>(
    context: context,
    builder: (_) => AddRelayDialog(existing: current, fetcher: fetcher),
  );
  if (added == null) return;
  try {
    await setter(
      [...current, added.url],
      info: {if (added.info != null) added.url: added.info!},
    );
    messenger.showSnackBar(SnackBar(content: Text(l.relayAdded)));
  } catch (e) {
    errors.show(e);
  }
}

Future<void> _restoreDefaults(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final errors = ActionErrors.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(linkRelaysSetterProvider)(kDefaultLinkRelays);
    messenger.showSnackBar(SnackBar(content: Text(l.relaysDefaultsRestored)));
  } catch (e) {
    errors.show(e);
  }
}

class _RelayTile extends ConsumerWidget {
  final LinkRelayView relay;
  final bool canRemove;
  final List<String> all;
  const _RelayTile({
    required this.relay,
    required this.canRemove,
    required this.all,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final now = ref.watch(relaySettingsClockProvider)();
    final label = relayLabel(relay.url);
    final status = relayStatusOf(relay);
    final text = switch (status.kind) {
      RelayStatusKind.rejects => l.relayStatusRejects(status.message ?? ''),
      RelayStatusKind.rateLimited => l.relayStatusRateLimited(
        ((status.at! - now.millisecondsSinceEpoch) / 60000).ceil().clamp(
          1,
          999,
        ),
      ),
      RelayStatusKind.unsuitable => switch (status.problem!) {
        RelayInfoProblem.needsAccount => l.relayStatusNeedsAccount,
        RelayInfoProblem.noExpiration => l.relayStatusNoExpiration,
      },
      RelayStatusKind.lastRefused => l.relayStatusLastRefused(
        agoText(l, status.at!, now: now),
        status.message ?? '',
      ),
      RelayStatusKind.ok => l.relayStatusOk(agoText(l, status.at!, now: now)),
      RelayStatusKind.unused => l.relayStatusUnused,
    };
    final terms = relayTermsUrl(relay);
    return ListTile(
      key: Key('relay-$label'),
      leading: Icon(
        status.isProblem ? Icons.error_outline : Icons.hub_outlined,
        color: status.isProblem ? theme.colorScheme.error : null,
      ),
      title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        text,
        style: status.isProblem
            ? TextStyle(color: theme.colorScheme.error)
            : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (terms != null)
            IconButton(
              key: Key('relayTerms-$label'),
              icon: const Icon(Icons.description_outlined),
              tooltip: l.relayTermsOf(label),
              onPressed: () => launchUrl(
                Uri.parse(terms),
                mode: LaunchMode.externalApplication,
              ),
            ),
          IconButton(
            key: Key('relayRemove-$label'),
            icon: const Icon(Icons.delete_outline),
            tooltip: l.relayRemove(label),
            onPressed: canRemove ? () => _remove(context, ref, label) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    String label,
  ) async {
    final l = context.l10n;
    final errors = ActionErrors.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final setter = ref.read(linkRelaysSetterProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.relayRemoveConfirmTitle(label)),
        content: Text(l.relayRemoveConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const Key('relayRemoveConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.relayRemoveConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await setter([
        for (final r in all)
          if (r != relay.url) r,
      ]);
      messenger.showSnackBar(SnackBar(content: Text(l.relayRemoved)));
    } catch (e) {
      errors.show(e);
    }
  }
}

/// *Add relay…*: the address, then the NIP-11 check (§4.6). Pops the
/// relay URL and its document (null info = added without a check).
class AddRelayDialog extends StatefulWidget {
  final List<String> existing;
  final RelayInfoFetcher? fetcher;
  const AddRelayDialog({super.key, required this.existing, this.fetcher});

  @override
  State<AddRelayDialog> createState() => _AddRelayDialogState();
}

class _AddRelayDialogState extends State<AddRelayDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _checking = false;

  /// The NIP-11 check failed for this URL — offer *Add anyway*.
  String? _unchecked;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final unchecked = _unchecked;
    if (unchecked != null) {
      Navigator.pop(context, (url: unchecked, info: null));
      return;
    }
    final parsed = parseRelayInput(_ctrl.text, widget.existing);
    if (parsed.problem != null) {
      setState(
        () => _error = switch (parsed.problem!) {
          RelayInputProblem.invalid => l.relayAddInvalid,
          RelayInputProblem.notSecure => l.relayAddNotSecure,
          RelayInputProblem.duplicate => l.relayAddDuplicate,
        },
      );
      return;
    }
    final url = parsed.url!;
    final fetcher = widget.fetcher;
    if (fetcher == null) {
      setState(() => _unchecked = url);
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    RelayInfo? info;
    try {
      info = await fetcher.fetch(url);
    } catch (_) {
      info = null;
    }
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _checking = false;
        _unchecked = url;
      });
      return;
    }
    final problem = relayInfoProblem(info);
    if (problem != null) {
      setState(() {
        _checking = false;
        _error = switch (problem) {
          RelayInfoProblem.needsAccount => l.relayAddNeedsAccount,
          RelayInfoProblem.noExpiration => l.relayAddNoExpiration,
        };
      });
      return;
    }
    Navigator.pop(context, (url: url, info: info));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.relayAddTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('relayAddField'),
            controller: _ctrl,
            autofocus: true,
            enabled: !_checking,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l.relayAddLabel,
              hintText: 'wss://relay.example.org',
              errorText: _error,
              errorMaxLines: 4,
            ),
            onChanged: (_) {
              if (_error != null || _unchecked != null) {
                setState(() {
                  _error = null;
                  _unchecked = null;
                });
              }
            },
            onSubmitted: (_) => _checking ? null : _submit(),
          ),
          if (_checking)
            Padding(
              padding: const EdgeInsets.only(top: Insets.m),
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: Insets.s),
                  Expanded(child: Text(l.relayAddChecking)),
                ],
              ),
            ),
          if (_unchecked != null)
            Padding(
              key: const Key('relayAddUnchecked'),
              padding: const EdgeInsets.only(top: Insets.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.relayAddUncheckedTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(l.relayAddUncheckedBody),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('relayAddConfirm'),
          onPressed: _checking ? null : _submit,
          child: Text(
            _unchecked != null ? l.relayAddAnyway : l.relayAddConfirm,
          ),
        ),
      ],
    );
  }
}
