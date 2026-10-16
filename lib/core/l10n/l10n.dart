/// Localization entry point (G12): `context.l10n.someKey` for strings and
/// `context.money(cents, currency)` / `context.date(ms)` for formatting in the
/// current locale. Strings live in `lib/l10n/app_<locale>.arb`.
library;

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import 'formatting.dart';

export '../../l10n/app_localizations.dart';
export 'formatting.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// The active locale name for `intl` (`en`, `de`).
  String get localeName => l10n.localeName;

  String money(int cents, String currency) =>
      formatMoney(cents, currency, localeName);

  String date(int msEpoch) => formatDate(msEpoch, localeName);
}
