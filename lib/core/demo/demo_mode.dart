/// Offline demo mode (G15): `--dart-define=OFFLINE_DEMO=true` starts the app
/// signed in as a demo user with a seeded ledger, an in-process fake relay and
/// fake auth — no homeserver, no network, no Matrix client. For screenshots,
/// store listings and quick manual UI checks.
///
/// A compile-time constant: in a normal build `kOfflineDemo` is `false`, so
/// every `if (kOfflineDemo)` branch (and the demo code only it reaches) is
/// tree-shaken away.
library;

const bool kOfflineDemo = bool.fromEnvironment('OFFLINE_DEMO');

/// The demo account ("Anna"). `example.org` is reserved (RFC 2606) — never a
/// real homeserver.
const kDemoUserId = '@anna:example.org';

/// The demo ledger's own database name. Deliberately outside the
/// `money_ledger_<hash>` per-account and `money_ledger_db` legacy names, so the
/// demo can never open (or adopt) a real account's ledger.
const kDemoDatabaseName = 'money_ledger_offline_demo';
