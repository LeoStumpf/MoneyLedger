/// Localization entry point (G12): `context.l10n.someKey` for strings and
/// `context.money(cents, currency)` / `context.date(ms)` for formatting in the
/// current locale. Strings live in `lib/l10n/app_<locale>.arb`.
library;

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import 'formatting.dart';

export '../../l10n/app_localizations.dart';
export 'currencies.dart';
export 'formatting.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// The active locale name for `intl` (`en`, `de`).
  String get localeName => l10n.localeName;

  String money(int cents, String currency) =>
      formatMoney(cents, currency, localeName);

  String date(int msEpoch) => formatDate(msEpoch, localeName);

  /// Date + time (G48 restore points / change list).
  String dateTime(int msEpoch) => formatDateTime(msEpoch, localeName);

  /// "Today" / "Yesterday" / a short weekday date — list section headers
  /// (G17).
  String dayHeader(int msEpoch, {DateTime? now}) =>
      switch (calendarDaysAgo(msEpoch, now: now)) {
        0 => l10n.today,
        1 => l10n.yesterday,
        _ => formatDayHeader(msEpoch, localeName, now: now),
      };

  /// Like [dayHeader] but lower-key for inline text: "today", or a date.
  String relativeDate(int msEpoch, {DateTime? now}) =>
      switch (calendarDaysAgo(msEpoch, now: now)) {
        0 => l10n.today,
        1 => l10n.yesterday,
        _ => formatDate(msEpoch, localeName),
      };
}

/// A coarse "x ago" (minutes / hours / days) — last-synced lines, the G68
/// sync sheet, relay status (G52 step 9).
String agoText(AppLocalizations l, int msEpoch, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(
    DateTime.fromMillisecondsSinceEpoch(msEpoch),
  );
  if (d.inMinutes < 1) return l.agoJustNow;
  if (d.inHours < 1) return l.agoMinutes(d.inMinutes);
  if (d.inDays < 1) return l.agoHours(d.inHours);
  return l.agoDays(d.inDays);
}
