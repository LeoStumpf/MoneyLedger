/// Localization helpers for tests (G12).
library;

import 'package:flutter/widgets.dart';
import 'package:money_ledger/l10n/app_localizations.dart';

export 'package:money_ledger/l10n/app_localizations.dart';

/// English strings — for pure-Dart tests of helpers that take an
/// [AppLocalizations] (no widget tree needed).
final en = lookupAppLocalizations(const Locale('en'));

/// German strings.
final de = lookupAppLocalizations(const Locale('de'));

/// Delegates for a test `MaterialApp`, so `AppLocalizations.of` works.
const testLocalizationsDelegates = AppLocalizations.localizationsDelegates;
const testSupportedLocales = AppLocalizations.supportedLocales;
