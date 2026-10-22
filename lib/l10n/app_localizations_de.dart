// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'MoneyLedger';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get save => 'Speichern';

  @override
  String get add => 'Hinzufügen';

  @override
  String get ok => 'OK';

  @override
  String get done => 'Fertig';

  @override
  String get required => 'Pflichtfeld';

  @override
  String get groupsTitle => 'Gruppen';

  @override
  String get devicesTooltip => 'Geräte & Sicherheit';

  @override
  String get settingsTooltip => 'Einstellungen';

  @override
  String get signOut => 'Abmelden';

  @override
  String get newGroup => 'Neue Gruppe';

  @override
  String get signOutConfirmTitle => 'Abmelden?';

  @override
  String get signOutConfirmBody =>
      'Deine Gruppen und Ausgaben bleiben auf diesem Gerät und sind wieder da, wenn du dich erneut mit diesem Konto anmeldest. Solange du abgemeldet bist, synchronisiert dieses Gerät nicht – Änderungen anderer Personen kommen an, sobald du dich wieder anmeldest.';

  @override
  String importFailed(Object error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String importedExpenses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ausgaben importiert',
      one: '1 Ausgabe importiert',
    );
    return '$_temp0';
  }

  @override
  String get noGroupsYet =>
      'Noch keine Gruppen.\nErstelle eine, um loszulegen.';

  @override
  String get restoringGroupsTitle =>
      'Deine Gruppen werden von deinen anderen Geräten wiederhergestellt …';

  @override
  String get restoringGroupsBody =>
      'Öffne MoneyLedger auf einem anderen Gerät, das mit diesem Konto angemeldet ist – es sendet deine Gruppen, solange die App dort läuft.';

  @override
  String get syncSettingsBody =>
      'Geräte tauschen Änderungen aus, solange MoneyLedger geöffnet ist. Änderungen anderer warten (verschlüsselt) auf deinem Homeserver, bis dieses Gerät sie abholt.';

  @override
  String get backgroundSyncTitle => 'Hintergrund-Synchronisierung';

  @override
  String get backgroundSyncBody =>
      'Auch etwa alle 15 Minuten synchronisieren, wenn die App geschlossen ist (mit Netzwerk, nicht bei niedrigem Akku).';

  @override
  String get noBackgroundSyncTitle => 'Hier keine Hintergrund-Synchronisierung';

  @override
  String get noBackgroundSyncBody =>
      'Im Browser synchronisiert MoneyLedger nur, solange dieser Tab geöffnet ist. Die Android-App synchronisiert zusätzlich regelmäßig im Hintergrund.';

  @override
  String backgroundSyncScheduleFailed(String error) {
    return 'Die Hintergrund-Synchronisierung konnte auf diesem Gerät nicht eingerichtet werden: $error';
  }

  @override
  String get encryptionUnavailableBanner =>
      'Die Verschlüsselung konnte auf diesem Gerät nicht gestartet werden, daher ist die Synchronisierung mit anderen Personen und Geräten aus. Deine Gruppen bleiben hier verfügbar. Starte die App neu; wenn das Problem bleibt, aktualisiere die App oder installiere sie neu.';

  @override
  String get aboutTitle => 'Über MoneyLedger';

  @override
  String get somethingWentWrong => 'Etwas ist schiefgelaufen';

  @override
  String get signOutAndRestart => 'Abmelden und neu starten';

  @override
  String get expensesTitle => 'Ausgaben';

  @override
  String get addMember => 'Person hinzufügen';

  @override
  String get membersTitle => 'Personen';

  @override
  String get balanceTitle => 'Saldo';

  @override
  String get moreTooltip => 'Mehr';

  @override
  String get editGroup => 'Gruppe bearbeiten';

  @override
  String get exportCsv => 'CSV exportieren';

  @override
  String get leaveGroup => 'Gruppe verlassen';

  @override
  String get deleteGroup => 'Gruppe löschen';

  @override
  String get addExpense => 'Ausgabe hinzufügen';

  @override
  String get removedFromGroupBanner =>
      'Du wurdest aus dieser Gruppe entfernt. Ihr Verlauf bleibt hier lesbar.';

  @override
  String get deleteFromThisDevice => 'Von diesem Gerät löschen';

  @override
  String get addedToGroupBanner =>
      'Du wurdest zu dieser Gruppe hinzugefügt. Welche Person bist du?';

  @override
  String get choose => 'Auswählen';

  @override
  String get noExpensesYet => 'Noch keine Ausgaben.';

  @override
  String get thisGroup => 'Diese Gruppe';

  @override
  String youLeftGroup(Object group) {
    return 'Du hast „$group“ verlassen';
  }

  @override
  String deletedGroup(Object group) {
    return '„$group“ gelöscht';
  }

  @override
  String exportedFile(Object fileName) {
    return '$fileName exportiert';
  }

  @override
  String get whichParticipantAreYou => 'Welche Person bist du?';

  @override
  String get imSomeoneNew => 'Ich bin neu dabei';

  @override
  String get yourName => 'Dein Name';

  @override
  String get nameLabel => 'Name';

  @override
  String get join => 'Beitreten';

  @override
  String get deleteExpenseTitle => 'Ausgabe löschen?';

  @override
  String deleteExpenseBody(Object description) {
    return '„$description“ wird für alle in der Gruppe entfernt.';
  }

  @override
  String get deleteSettlementTitle => 'Zahlung löschen?';

  @override
  String deleteSettlementBody(Object from, Object to, Object amount) {
    return '„$from hat $to $amount gezahlt“ wird für alle in der Gruppe entfernt und der Saldo wiederhergestellt.';
  }

  @override
  String get matrixIdLabel => 'Matrix-ID';

  @override
  String addedMember(Object userId) {
    return '$userId hinzugefügt';
  }

  @override
  String get syncProblemTooltip =>
      'Synchronisierungsproblem – für Details tippen';

  @override
  String get syncedWithAll => 'Mit allen in der Gruppe synchronisiert';

  @override
  String peerHasNoDevice(Object peer) {
    return '$peer hat kein aktives Gerät – wird synchronisiert, sobald sich die Person anmeldet';
  }

  @override
  String waitingForPeer(Object peer) {
    return 'Warte auf $peer …';
  }

  @override
  String get syncProblemTitle => 'Synchronisierungsproblem';

  @override
  String get syncProblemBody =>
      'Die anderen in der Gruppe waren nicht erreichbar. Deine Änderungen sind auf diesem Gerät gespeichert und werden synchronisiert, sobald die Verbindung wieder steht.';

  @override
  String lastSynced(Object ago) {
    return 'Zuletzt synchronisiert: $ago';
  }

  @override
  String lastError(Object error) {
    return 'Letzter Fehler: $error';
  }

  @override
  String get retryingSync => 'Synchronisierung wird wiederholt …';

  @override
  String get retryNow => 'Jetzt wiederholen';

  @override
  String get agoJustNow => 'gerade eben';

  @override
  String agoMinutes(int n) {
    return 'vor $n Min.';
  }

  @override
  String agoHours(int n) {
    return 'vor $n Std.';
  }

  @override
  String agoDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'vor $n Tagen',
      one: 'vor 1 Tag',
    );
    return '$_temp0';
  }

  @override
  String paidByName(Object name) {
    return 'Bezahlt von $name';
  }

  @override
  String get expenseOptions => 'Optionen für die Ausgabe';

  @override
  String settlementTitle(Object from, Object to) {
    return '$from hat $to bezahlt';
  }

  @override
  String settlementSubtitle(Object date) {
    return 'Zahlung · $date';
  }

  @override
  String get settlementOptions => 'Optionen für die Zahlung';

  @override
  String get editExpense => 'Ausgabe bearbeiten';

  @override
  String get descriptionLabel => 'Beschreibung';

  @override
  String get amountLabel => 'Betrag';

  @override
  String get invalidNumber => 'Ungültige Zahl';

  @override
  String get currencyLabel => 'Währung';

  @override
  String get paidByLabel => 'Bezahlt von';

  @override
  String get splitEqual => 'Gleich';

  @override
  String get splitExact => 'Beträge';

  @override
  String get splitShares => 'Anteile';

  @override
  String get splitPercent => 'Prozent';

  @override
  String get splitSelectAtLeastOne => 'Wähle mindestens eine Person aus';

  @override
  String splitEquallyAmong(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Gleichmäßig auf $n Personen aufgeteilt',
      one: 'Gleichmäßig auf 1 Person aufgeteilt',
    );
    return '$_temp0';
  }

  @override
  String get splitAddsUpToTotal => 'Ergibt den Gesamtbetrag';

  @override
  String splitLeft(Object amount) {
    return 'noch $amount offen';
  }

  @override
  String splitTooMuch(Object amount) {
    return '$amount zu viel';
  }

  @override
  String splitPercentValue(Object value) {
    return '$value %';
  }

  @override
  String get splitEnterAmountFirst => 'Gib zuerst den Betrag ein';

  @override
  String get splitDistribute => 'Verteilen';

  @override
  String get splitRescale => 'Proportional anpassen';

  @override
  String get splitSetTotalToSum => 'Gesamtbetrag auf die Summe setzen';

  @override
  String splitTotalSetTo(String amount) {
    return 'Gesamtbetrag auf $amount gesetzt';
  }

  @override
  String get splitFineTuneAsAmounts => 'Als Beträge feinjustieren';

  @override
  String get splitPutRestHere => 'Rest hier eintragen';

  @override
  String get splitShareMore => 'Ein Anteil mehr';

  @override
  String get splitShareLess => 'Ein Anteil weniger';

  @override
  String get splitOpenFieldsHint =>
      'Leere Felder teilen sich den Rest · 0 = nicht beteiligt';

  @override
  String get splitByWeight => 'Nach Anteilen aufgeteilt';

  @override
  String get splitEnterWeight => 'Gib mindestens einen Anteil ein';

  @override
  String get splitAddsUpTo100 => 'Ergibt 100 %';

  @override
  String get splitPercentMustTotal100 =>
      'Die Prozente müssen zusammen 100 % ergeben';

  @override
  String get recordPayment => 'Zahlung erfassen';

  @override
  String get allSettledUp => 'Alles ausgeglichen!';

  @override
  String owesName(Object name) {
    return 'schuldet $name';
  }

  @override
  String get paymentRecorded => 'Zahlung erfasst';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get editPayment => 'Zahlung bearbeiten';

  @override
  String get paymentUpdated => 'Zahlung aktualisiert';

  @override
  String get paymentGone =>
      'Diese Zahlung wurde inzwischen gelöscht – nichts wurde geändert.';

  @override
  String get paymentFromLabel => 'Von (hat gezahlt)';

  @override
  String get paymentToLabel => 'An (hat erhalten)';

  @override
  String paymentExceedsDebt(Object amount) {
    return 'Mehr als die geschuldeten $amount';
  }

  @override
  String get record => 'Erfassen';

  @override
  String unsettledYouOwe(Object amount) {
    return 'Du schuldest noch $amount.';
  }

  @override
  String unsettledYouAreOwed(Object amount) {
    return 'Dir werden noch $amount geschuldet.';
  }

  @override
  String get leaveGroupTitle => 'Gruppe verlassen?';

  @override
  String get deleteGroupTitle => 'Gruppe löschen?';

  @override
  String leaveGroupBody(Object group) {
    return '„$group“ wird von diesem Gerät entfernt, und die anderen in der Gruppe sehen, dass du gegangen bist. Deine Ausgaben bleiben in ihrem Kassenbuch.';
  }

  @override
  String deleteGroupBody(Object group) {
    return '„$group“ und alle Ausgaben darin werden dauerhaft von diesem Gerät entfernt.';
  }

  @override
  String get backupBeforeExitTip =>
      'Tipp: Sichere vorher alle Gruppen (Einstellungen → Sichern & Wiederherstellen).';

  @override
  String get backupBeforeExit => 'Vorher alle Gruppen sichern';

  @override
  String get leave => 'Verlassen';

  @override
  String get groupNameLabel => 'Gruppenname';

  @override
  String get defaultCurrencyLabel => 'Standardwährung';

  @override
  String get defaultCurrencyHelper =>
      'Gilt nur für neue Ausgaben – bestehende Ausgaben behalten ihre Währung.';

  @override
  String get create => 'Erstellen';

  @override
  String get inviteByMatrixId => 'Per Matrix-ID einladen';

  @override
  String get addPerson => 'Person hinzufügen';

  @override
  String get noMembers => 'Noch niemand in dieser Gruppe.';

  @override
  String get formerMembers => 'Nicht mehr dabei';

  @override
  String get invite => 'Einladen';

  @override
  String invitedMember(Object userId) {
    return '$userId eingeladen';
  }

  @override
  String get nameHint => 'z. B. Alex';

  @override
  String get matrixIdOptionalLabel => 'Matrix-ID (optional)';

  @override
  String get matrixIdOptionalHint =>
      '@user:server – leer lassen für eine lokale Person';

  @override
  String get invalidMatrixId => 'Ungültige Matrix-ID';

  @override
  String formerMemberClaimed(Object matrixId) {
    return '$matrixId · nicht mehr dabei';
  }

  @override
  String get formerMemberLocal => 'Lokal · nicht mehr dabei';

  @override
  String get formerMemberTag => 'nicht mehr dabei';

  @override
  String get you => 'Du';

  @override
  String get readd => 'Wieder hinzufügen';

  @override
  String readdedMember(Object name) {
    return '$name wieder hinzugefügt';
  }

  @override
  String get localParticipant => 'Lokal';

  @override
  String get options => 'Optionen';

  @override
  String get rename => 'Umbenennen';

  @override
  String get detachMatrixAccount => 'Matrix-Konto trennen';

  @override
  String get linkMatrixAccount => 'Matrix-Konto verknüpfen';

  @override
  String get removeFromGroup => 'Aus Gruppe entfernen';

  @override
  String removeMemberBody(Object name) {
    return '$name aus dieser Gruppe entfernen?\n\nDer Ausgabenverlauf bleibt erhalten, die Person ist danach nur nicht mehr dabei.';
  }

  @override
  String get remove => 'Entfernen';

  @override
  String get onboardingAddTitle => 'Füge alle hinzu – mit oder ohne Matrix';

  @override
  String get onboardingAddBody =>
      'Lade Personen über ihre Matrix-ID ein oder füge sie nur mit Namen hinzu und verknüpfe später ein Konto.';

  @override
  String get getStarted => 'Los geht\'s';

  @override
  String get devicesTitle => 'Geräte';

  @override
  String get thisDevice => 'Dieses Gerät';

  @override
  String get verified => 'Verifiziert';

  @override
  String get notVerified => 'Nicht verifiziert';

  @override
  String get verify => 'Verifizieren';

  @override
  String verifyDeviceTitle(Object device) {
    return '$device verifizieren';
  }

  @override
  String get verifyCompareEmoji =>
      'Bestätige, dass diese Emojis auf dem anderen Gerät in derselben Reihenfolge erscheinen.';

  @override
  String get deviceVerified => 'Gerät verifiziert.';

  @override
  String get verificationFailed => 'Verifizierung fehlgeschlagen.';

  @override
  String verificationFailedWithError(Object error) {
    return 'Verifizierung fehlgeschlagen: $error.';
  }

  @override
  String get emojiNoMatch => 'Sie stimmen nicht überein';

  @override
  String get emojiMatch => 'Sie stimmen überein';

  @override
  String get onlyDevice => 'Das ist dein einziges Gerät.';

  @override
  String get allDevicesVerified => 'Alle deine Geräte sind verifiziert.';

  @override
  String devicesNeedVerification(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Geräte müssen verifiziert werden.',
      one: '1 Gerät muss verifiziert werden.',
    );
    return '$_temp0';
  }

  @override
  String authUnreachableTitle(Object host) {
    return '$host ist nicht erreichbar';
  }

  @override
  String get authUnreachableHint =>
      'Der Server ist vielleicht nicht erreichbar oder die Adresse falsch – oder du bist offline. Prüfe die Homeserver-Adresse und deine Internetverbindung.';

  @override
  String get authUnreachableNoHostTitle => 'Server nicht erreichbar';

  @override
  String get authTimeoutTitle => 'Der Server hat zu lange nicht geantwortet';

  @override
  String get authTimeoutHint =>
      'Prüfe deine Verbindung und versuche es erneut.';

  @override
  String authNotAHomeserverTitle(Object host) {
    return '$host scheint kein Matrix-Homeserver zu sein';
  }

  @override
  String get authNotAHomeserverHint =>
      'Prüfe die Adresse – zum Beispiel matrix.org.';

  @override
  String get authWrongCredentialsTitle =>
      'Falscher Benutzername oder falsches Passwort';

  @override
  String get authWrongCredentialsHint => 'Prüfe beides und versuche es erneut.';

  @override
  String get authDeactivatedTitle => 'Dieses Konto wurde deaktiviert';

  @override
  String get authDeactivatedHint =>
      'Wende dich an die Administration deines Homeservers oder nutze ein anderes Konto.';

  @override
  String get authRateLimitedTitle => 'Zu viele Versuche';

  @override
  String authRateLimitedRetry(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Bitte warte $seconds Sekunden und versuche es erneut.',
      one: 'Bitte warte 1 Sekunde und versuche es erneut.',
    );
    return '$_temp0';
  }

  @override
  String get authRateLimitedHint =>
      'Bitte warte einen Moment und versuche es erneut.';

  @override
  String get authSsoTokenTitle => 'Anmeldelink abgelaufen oder ungültig';

  @override
  String get authSsoTokenHint => 'Bitte starte die Anmeldung erneut.';

  @override
  String get authUsernameTakenTitle =>
      'Dieser Benutzername ist bereits vergeben';

  @override
  String get authUsernameTakenHint => 'Wähle einen anderen Benutzernamen.';

  @override
  String get authInvalidUsernameTitle =>
      'Dieser Benutzername ist nicht erlaubt';

  @override
  String get authInvalidUsernameHint =>
      'Verwende nur Kleinbuchstaben, Ziffern und . _ = - /';

  @override
  String get authWeakPasswordTitle => 'Das Passwort ist zu schwach';

  @override
  String get authWeakPasswordHint =>
      'Verwende ein längeres Passwort mit Buchstaben, Ziffern und Sonderzeichen.';

  @override
  String get authRegistrationDisabledTitle =>
      'Dieser Homeserver erlaubt hier keine Registrierung';

  @override
  String get authRegistrationDisabledHint =>
      'Erstelle dein Konto auf seiner Website und melde dich dann an.';

  @override
  String get authUnknownTitle => 'Etwas ist schiefgelaufen';

  @override
  String get authUnknownHint =>
      'Bitte versuche es erneut. Die Details unten helfen vielleicht weiter.';

  @override
  String get authErrorDetails => 'Details';

  @override
  String get signInSubtitle => 'Melde dich mit deinem Matrix-Konto an';

  @override
  String get homeserverLabel => 'Homeserver';

  @override
  String get homeserverHint => 'z. B. matrix.org';

  @override
  String get checkServerTooltip => 'Server prüfen';

  @override
  String resolvedTo(Object url) {
    return 'Aufgelöst zu $url';
  }

  @override
  String continueWith(Object provider) {
    return 'Weiter mit $provider';
  }

  @override
  String get orDivider => 'oder';

  @override
  String get matrixIdOrUsernameLabel => 'Matrix-ID oder Benutzername';

  @override
  String get passwordLabel => 'Passwort';

  @override
  String get signIn => 'Anmelden';

  @override
  String get createAccountLink => 'Neu hier? Konto erstellen';

  @override
  String get createAccount => 'Konto erstellen';

  @override
  String get usernameLabel => 'Benutzername';

  @override
  String get passwordMinLength => 'Mindestens 8 Zeichen';

  @override
  String get alreadyHaveAccount => 'Schon ein Konto? Anmelden';

  @override
  String get registerOnWebTitle => 'Im Web registrieren';

  @override
  String registerOnWebBody(Object requirements) {
    return 'Dieser Homeserver verlangt $requirements, was MoneyLedger in der App noch nicht kann. Erstelle dein Konto auf seiner Website, komm dann zurück und melde dich an.';
  }

  @override
  String get openHomeserverWebsite => 'Website des Homeservers öffnen';

  @override
  String listAnd(Object first, Object last) {
    return '$first und $last';
  }

  @override
  String get regReqExtraVerification => 'eine zusätzliche Verifizierung';

  @override
  String get regReqCaptcha => 'ein CAPTCHA';

  @override
  String get regReqEmail => 'eine E-Mail-Bestätigung';

  @override
  String get regReqPhone => 'eine Telefonbestätigung';

  @override
  String get regReqTerms => 'das Akzeptieren der Nutzungsbedingungen';

  @override
  String get regReqToken => 'einen Registrierungscode';

  @override
  String get regReqWebSignup => 'die Registrierung auf seiner eigenen Website';

  @override
  String get aboutAndPrivacy => 'Info & Datenschutz';

  @override
  String aboutVersion(Object version) {
    return 'Version $version';
  }

  @override
  String get aboutDescription =>
      'Teile Ausgaben mit Freunden – dezentral und Ende-zu-Ende-verschlüsselt über Matrix. Dein Kassenbuch bleibt auf deinen Geräten; es gibt keinen MoneyLedger-Server.';

  @override
  String get aboutSourceCode => 'Quellcode';

  @override
  String get aboutLicense => 'Lizenz';

  @override
  String aboutLicenseValue(Object license) {
    return '$license – freie Software: Du darfst sie nutzen, untersuchen, weitergeben und verändern.';
  }

  @override
  String aboutLegalese(Object license) {
    return '© Leo Stumpf. Lizenziert unter der $license.';
  }

  @override
  String get aboutOpenSourceLicenses => 'Open-Source-Lizenzen';

  @override
  String get privacyPolicyTitle => 'Datenschutzerklärung';

  @override
  String privacyLastUpdated(Object date) {
    return 'Stand: $date';
  }

  @override
  String get privacyIntro =>
      'MoneyLedger ist eine App zum Teilen von Ausgaben ohne zentralen Server. Sie hat kein eigenes Kontosystem – du meldest dich mit deinem Matrix-Konto an oder nutzt die App ganz ohne Konto (lokaler Modus) –, zeigt keine Werbung, enthält keine Analyse- oder Tracking-Funktionen und verkauft oder teilt deine Daten nicht. MoneyLedger wird von Leo Stumpf veröffentlicht, einem einzelnen Entwickler. Es gibt keinen MoneyLedger-Server, der deine Daten empfangen könnte.';

  @override
  String get privacyLedgerTitle => 'Dein Kassenbuch bleibt auf deinen Geräten';

  @override
  String get privacyLedgerBody =>
      'Gruppen, Personen, Ausgaben und Zahlungen werden nur in einer lokalen Datenbank auf jedem Gerät gespeichert, das mit dem Konto einer Person aus der Gruppe angemeldet ist. Alle in einer Gruppe haben eine Kopie des Kassenbuchs der Gruppe – so funktioniert das Teilen: Namen, Matrix-IDs, Ausgaben und Zahlungen einer Gruppe sind für alle in der Gruppe sichtbar.';

  @override
  String get privacyHomeserverTitle => 'Was dein Matrix-Homeserver sieht';

  @override
  String get privacyHomeserverBody =>
      'Zum Synchronisieren sendet MoneyLedger jede Änderung als Ende-zu-Ende-verschlüsselte Matrix-Nachricht (to-device) an die Geräte der anderen in der Gruppe. Dein Homeserver (und deren Homeserver) leiten diese Nachrichten weiter und halten jede nur so lange vor, bis das empfangende Gerät sie abgeholt hat, können sie aber nicht lesen. Sie sehen allerdings Metadaten: welche Konten und Geräte Nachrichten austauschen, wann, wie oft und ungefähr wie groß. MoneyLedger legt keine Räume an, speichert nichts in den Einstellungen deines Kontos und zeigt dich nie als online an; beim Synchronisieren fragt es deinen Homeserver nur nach diesen Nachrichten und nach Änderungen an Schlüsseln – nicht nach deinen Räumen, deinem Online-Status oder deinen Kontoeinstellungen. Was dein Homeserver dennoch speichert, braucht jede Matrix-App: dein Konto, die Liste seiner Geräte (dieses heißt „MoneyLedger“, mit Zeitpunkt und IP-Adresse der letzten Nutzung), die öffentlichen Schlüssel und Einmalschlüssel jedes Geräts sowie die Nachrichten oben bis zur Zustellung (für ein Gerät, das nie wiederkommt, bis es entfernt wird). Dein Matrix-Konto selbst – Benutzername, Geräte, Schlüssel, IP-Adressen und Anmeldeverlauf – verarbeitet dein Homeserver nach seiner eigenen Datenschutzerklärung.';

  @override
  String get privacyNoTrackingTitle => 'Keine Analyse, keine eigenen Server';

  @override
  String get privacyNoTrackingBody =>
      'Abgesehen von den Nostr-Relays der Gruppen, die du mit einem Einladungslink teilst (siehe „Geteilte Gruppen (Einladungslink)“) und dem Wechselkurs-Dienst, den du mit „Aktuellen Kurs abrufen“ fragen kannst (siehe „Wechselkurse“), kommuniziert die App nur mit Matrix-Homeservern: auf der Anmeldeseite mit dem Server, den du einträgst – und erst, wenn du ihn bestätigst oder dich anmeldest –, danach nur mit deinem eigenen Homeserver. Über ihn fragt sie auch die Matrix-Profilnamen und Geräte der Personen in deinen Gruppen ab (dein Homeserver fragt dafür ggf. deren Homeserver). Wenn du Single Sign-on nutzt oder dich im Web registrierst, öffnet dein Browser die Seiten, zu denen dich dein Homeserver schickt (bei matrix.org ggf. die Registrierungsseite von Element, app.element.io). Links in der App – etwa zum Quellcode auf GitHub – öffnen sich erst in deinem Browser, wenn du darauf tippst. Die Web-Version wird vollständig von der Seite geladen, auf der sie bereitgestellt wird: kein Code und keine Schriften von Google oder anderen Dritten. Es gibt keine Analyse, keine Absturzberichte, keine Werbe-ID und keinerlei Tracking.';

  @override
  String get privacyBackgroundTitle =>
      'Hintergrund-Synchronisierung unter Android';

  @override
  String get privacyBackgroundBody =>
      'Unter Android kann MoneyLedger etwa alle 15 Minuten synchronisieren, während die App geschlossen ist (nur mit Netzwerkverbindung und nicht bei niedrigem Akku). Dafür werden dieselben verschlüsselten Nachrichten an deinen Homeserver genutzt und, für Gruppen, die du per Einladungslink teilst, dieselben verschlüsselten Kopien auf den Nostr-Relays (auch ohne Konto). Findet MoneyLedger dabei Ausgaben oder Zahlungen, die jemand anderes eingetragen, geändert oder gelöscht hat, zeigt die App eine Benachrichtigung mit dem Namen der Gruppe, wer es war, der Beschreibung und dem Betrag (standardmäßig an; Einstellungen → Synchronisierung → Benachrichtigungen). Diese Benachrichtigungen entstehen auf dem Gerät selbst – kein Push-Dienst, kein Google oder Firebase, dafür wird nichts gesendet – und auf dem Sperrbildschirm gilt die Android-Einstellung für vertrauliche Inhalte. Mit einem Matrix-Konto kannst du die Hintergrund-Synchronisierung in den Einstellungen abschalten; ohne Konto läuft sie nur, solange du eine Gruppe per Einladungslink teilst. Die Web-Version synchronisiert nur, solange ihr Tab geöffnet ist, und zeigt keine Benachrichtigungen.';

  @override
  String get privacyCsvTitle => 'Export, Sicherung und Import';

  @override
  String get privacyCsvBody =>
      'Beim Export einer Gruppe entsteht eine CSV-Datei mit ihren Ausgaben, Zahlungen, den Namen der Personen und den Beträgen; eine Sicherung („Alle Gruppen sichern“ unter Einstellungen → Sichern & Wiederherstellen oder eine Gruppe über ihre Gruppeneinstellungen) schreibt eine JSON-Datei mit den Gruppen, inklusive der Matrix-IDs der Personen und gelöschter Einträge – und bei Gruppen, die du mit einem Einladungslink teilst, deren Einladungsschlüssel: Wer die Datei hat, kann diese Gruppen lesen und ändern. Beides passiert nur, wenn du es auslöst. Wohin die Datei geht, entscheidest du. Eine CSV ist immer reiner Text; eine Sicherung ebenfalls, außer du legst eine Passphrase fest – dann wird sie auf deinem Gerät verschlüsselt (Argon2id + AES-256-GCM) und lässt sich nur mit dieser Passphrase wiederherstellen, die MoneyLedger weder speichert noch irgendwohin sendet. MoneyLedger hat danach keinen Einblick mehr in die Datei. Beim Import oder Wiederherstellen wird nur die Datei gelesen, die du auswählst.';

  @override
  String get privacyBackupTitle => 'Gerätesicherungen';

  @override
  String get privacyBackupBody =>
      'MoneyLedger nimmt nicht an der automatischen App-Sicherung und Geräteübertragung von Android teil. Dein Kassenbuch und deine Matrix-Sitzung (inklusive ihrer Schlüssel) werden von Android nie in eine Google-Sicherung oder auf ein anderes Telefon kopiert. Auf einem neuen Gerät meldest du dich an und deine Gruppen werden von deinen anderen Geräten und den anderen Personen in deinen Gruppen wiederhergestellt; für Gruppen, die nur du nutzt, ist eine Sicherungsdatei (Einstellungen → Sichern & Wiederherstellen) deine eigene Offline-Kopie.';

  @override
  String get privacyDeleteTitle => 'Deine Daten löschen';

  @override
  String get privacyDeleteBody =>
      '• Gruppe verlassen oder löschen (Gruppeneinstellungen): Sie wird samt allen Einträgen von diesem Gerät entfernt (die täglichen Wiederherstellungspunkte behalten sie etwa fünf Wochen – siehe oben). Wenn du sie verlässt, erfahren die anderen in der Gruppe davon.\n• Beim Abmelden bleibt das Kassenbuch dieses Kontos auf dem Gerät, damit es bei der nächsten Anmeldung wieder da ist.\n• Im lokalen Modus entfernt Einstellungen → Lokale Daten löschen alle lokalen Gruppen von diesem Gerät und beendet den lokalen Modus.\n• Wenn du die App deinstallierst (oder ihren Speicher löschst), wird alles entfernt, was sie auf dem Gerät gespeichert hat.\n• Kopien auf den Geräten anderer Personen gehören ihnen: Sie behalten den Verlauf der Gruppe, einschließlich deiner Ausgaben darin.\n• Dein Matrix-Konto kannst du über deinen Homeserver deaktivieren.';

  @override
  String get privacyContactTitle => 'Kontakt';

  @override
  String get privacyContactBody =>
      'Fragen oder etwas, das hier nicht stimmt: Eröffne ein Issue unter https://github.com/LeoStumpf/MoneyLedger oder schreib an leo.m.stumpf@gmail.com.';

  @override
  String youAreOwedAmount(String amount) {
    return 'Du bekommst $amount';
  }

  @override
  String youOweAmount(String amount) {
    return 'Du schuldest $amount';
  }

  @override
  String get settledUp => 'Ausgeglichen';

  @override
  String get notParticipating => 'Du bist nicht dabei';

  @override
  String lastActivity(String date) {
    return 'Zuletzt aktiv: $date';
  }

  @override
  String get totalOwedLabel => 'Du bekommst';

  @override
  String get totalOwingLabel => 'Du schuldest';

  @override
  String get totalNothing => 'Nichts';

  @override
  String get overallSettledUp => 'Alles ausgeglichen';

  @override
  String get overviewTitle => 'Über alle Gruppen';

  @override
  String get groupsEmptyTitle => 'Noch keine Gruppen';

  @override
  String get groupsEmptyBody =>
      'Lege eine Gruppe für eine Reise, deine WG oder ein Abendessen an – und füge die Personen hinzu, mit denen du Kosten teilst.';

  @override
  String get createGroup => 'Gruppe erstellen';

  @override
  String get importCsv => 'CSV importieren';

  @override
  String membersCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Personen',
      one: '1 Person',
    );
    return '$_temp0';
  }

  @override
  String get today => 'Heute';

  @override
  String get yesterday => 'Gestern';

  @override
  String get youPaid => 'Du hast bezahlt';

  @override
  String youLentAmount(String amount) {
    return 'du bekommst $amount';
  }

  @override
  String youBorrowedAmount(String amount) {
    return 'du schuldest $amount';
  }

  @override
  String get notInvolved => 'nicht beteiligt';

  @override
  String settlementYouPaid(String to) {
    return 'Du hast $to bezahlt';
  }

  @override
  String settlementPaidYou(String from) {
    return '$from hat dich bezahlt';
  }

  @override
  String get paymentLabel => 'Zahlung';

  @override
  String get yourBalance => 'Dein Saldo';

  @override
  String get settleUp => 'Begleichen';

  @override
  String get balancesButton => 'Salden';

  @override
  String get balancesSection => 'Salden';

  @override
  String get suggestedPayments => 'Vorgeschlagene Zahlungen';

  @override
  String get suggestedPaymentsHint =>
      'Tippe auf eine Zahlung, sobald sie erfolgt ist, um sie zu erfassen.';

  @override
  String get balanceGetsBack => 'bekommt';

  @override
  String get balanceOwes => 'schuldet';

  @override
  String get balanceYouGetBack => 'du bekommst';

  @override
  String get balanceYouOwe => 'du schuldest';

  @override
  String get balanceSettled => 'ausgeglichen';

  @override
  String debtPays(String from, String to) {
    return '$from zahlt an $to';
  }

  @override
  String get allSettledUpBody =>
      'In dieser Gruppe schuldet niemand jemandem etwas.';

  @override
  String get expensesEmptyTitle => 'Noch keine Ausgaben';

  @override
  String get expensesEmptyBody =>
      'Füge die erste Ausgabe hinzu – MoneyLedger rechnet aus, wer wem was schuldet.';

  @override
  String get expensesEmptyAloneBody =>
      'Bisher bist nur du in der Gruppe. Füge die Personen hinzu, mit denen du Kosten teilst – danach die erste Ausgabe.';

  @override
  String get addPeople => 'Personen hinzufügen';

  @override
  String get splitSection => 'Aufteilung';

  @override
  String get nameOptionalHelper =>
      'Mit Matrix-ID optional – dann wird ihr Profilname verwendet';

  @override
  String get nameOrMatrixIdRequired =>
      'Gib einen Namen oder eine Matrix-ID ein';

  @override
  String get next => 'Weiter';

  @override
  String get skip => 'Überspringen';

  @override
  String get localPerson => 'Lokale Person';

  @override
  String debtYouPay(String to) {
    return 'Du zahlst an $to';
  }

  @override
  String debtPaysYou(String from) {
    return '$from zahlt an dich';
  }

  @override
  String get backupExportTitle => 'Alle Gruppen sichern';

  @override
  String get backupExportBody =>
      'Speichert alle Gruppen – mit Zahlungen und gelöschten Einträgen – in einer Datei, auf Wunsch mit einer Passphrase verschlüsselt. Ohne Passphrase ist sie reiner Text: Bewahre sie sicher auf.';

  @override
  String get backupRestoreTitle => 'Aus Sicherung wiederherstellen';

  @override
  String get backupRestoreBody =>
      'Führt eine Sicherungsdatei mit diesem Gerät zusammen. Neuere Einträge gewinnen, nichts wird doppelt angelegt.';

  @override
  String lastBackupAt(String date) {
    return 'Letzte Sicherung: $date';
  }

  @override
  String get lastBackupNever => 'Letzte Sicherung: noch nie';

  @override
  String backupSaved(String fileName) {
    return 'Sicherung gespeichert: $fileName';
  }

  @override
  String get backupNotABackup => 'Diese Datei ist keine MoneyLedger-Sicherung.';

  @override
  String backupNewerVersion(int version) {
    return 'Diese Sicherung stammt von einer neueren MoneyLedger-Version (Format $version). Aktualisiere die App, um sie wiederherzustellen.';
  }

  @override
  String get backupMalformed =>
      'Diese Sicherungsdatei ist beschädigt und kann nicht wiederhergestellt werden.';

  @override
  String get restorePreviewTitle => 'Sicherung wiederherstellen?';

  @override
  String restoreBackupFrom(String date) {
    return 'Sicherung vom $date';
  }

  @override
  String restoreOtherAccount(String account) {
    return 'Diese Sicherung stammt von $account. Ihre Gruppen werden dem Konto hinzugefügt, mit dem du angemeldet bist.';
  }

  @override
  String restoreLocalIntoAccount(String account) {
    return 'Diese Sicherung wurde ohne Matrix-Konto erstellt. Beim Wiederherstellen übernimmt $account ihre Gruppen: Du bist dort mit diesem Konto dabei, und dieses Gerät signiert deine Einträge, damit sie synchronisiert werden können.';
  }

  @override
  String restoreAccountIntoLocal(String account) {
    return 'Diese Sicherung gehört zum Matrix-Konto $account. Hier nimmst du in ihren Gruppen den Platz dieses Kontos ein; es wird nichts gesendet. Verbinde später $account, um sie wieder zu synchronisieren.';
  }

  @override
  String get restoreLocalOwnFile =>
      'Stelle nur eine Sicherung wieder her, die du selbst erstellt hast: Dieses Gerät signiert ihre Einträge als deine. Gruppen mit Matrix-Konten werden unsigniert wiederhergestellt und nicht synchronisiert.';

  @override
  String groupsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Gruppen',
      one: '1 Gruppe',
    );
    return '$_temp0';
  }

  @override
  String expensesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ausgaben',
      one: '1 Ausgabe',
    );
    return '$_temp0';
  }

  @override
  String paymentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Zahlungen',
      one: '1 Zahlung',
    );
    return '$_temp0';
  }

  @override
  String restoreNewGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neue Gruppen',
      one: '1 neue Gruppe',
      zero: 'Keine neuen Gruppen',
    );
    return '$_temp0';
  }

  @override
  String restoreChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge werden hinzugefügt oder aktualisiert.',
      one: '1 Eintrag wird hinzugefügt oder aktualisiert.',
      zero: 'Alles aus dieser Sicherung ist schon auf diesem Gerät.',
    );
    return '$_temp0';
  }

  @override
  String get restoreTagNew => 'neu';

  @override
  String get restoreTagLeft => 'früher verlassen – kommt zurück';

  @override
  String restoreTagChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen',
      one: '1 Änderung',
    );
    return '$_temp0';
  }

  @override
  String get restoreTagUpToDate => 'aktuell';

  @override
  String get restoreLeftNote =>
      'Gruppen, die du verlassen oder gelöscht hast, kommen auf diesem Gerät zurück. Haben dich die anderen aus einer Gruppe entfernt, kommt sie schreibgeschützt zurück (nur der Verlauf) – eine Entfernung nach dieser Sicherung zeigt sich bei der nächsten Synchronisierung.';

  @override
  String get restoreAction => 'Wiederherstellen';

  @override
  String restoredGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Gruppen wiederhergestellt',
      one: '1 Gruppe wiederhergestellt',
    );
    return '$_temp0';
  }

  @override
  String get backupNudgeTitle => 'Sichere deine Gruppen';

  @override
  String backupNudgeBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Gruppen gibt es nur auf diesem Gerät. Geht es verloren, sind sie weg – speichere eine Sicherung.',
      one:
          '1 Gruppe gibt es nur auf diesem Gerät. Geht es verloren, ist die Gruppe weg – speichere eine Sicherung.',
    );
    return '$_temp0';
  }

  @override
  String backupNudgeLinkBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Wer den Link hat, kann deine $count Link-Gruppen ändern oder leeren – eine Sicherung schützt dich.',
      one:
          'Wer den Link hat, kann deine Link-Gruppe ändern oder leeren – eine Sicherung schützt dich.',
    );
    return '$_temp0';
  }

  @override
  String get backupNudgeLater => 'Später';

  @override
  String get backupNudgeAction => 'Jetzt sichern';

  @override
  String get onboardingBackupTitle => 'Leg eine Kopie an';

  @override
  String get onboardingBackupBody =>
      'Niemand sonst speichert deine Daten. Gruppen mit anderen Personen liegen auch auf deren Geräten. Für Gruppen, die nur du nutzt, melde dich auf einem zweiten Gerät an oder speichere ab und zu eine Sicherung (Einstellungen → Sichern & Wiederherstellen).';

  @override
  String get csvPreviewTitle => 'CSV importieren?';

  @override
  String csvPreviewNewGroup(String name) {
    return 'Legt die neue Gruppe „$name“ an.';
  }

  @override
  String csvPreviewExistingGroup(String name) {
    return 'Wird mit deiner Gruppe „$name“ zusammengeführt. Neuere Einträge gewinnen.';
  }

  @override
  String csvPreviewUnmatched(String names) {
    return 'Nicht in der Gruppe gefunden – werden als neue Personen hinzugefügt: $names';
  }

  @override
  String csvPreviewAmbiguous(String names) {
    return 'Mehrere Personen heißen gleich – die aktive wird verwendet: $names';
  }

  @override
  String get csvImportAction => 'Importieren';

  @override
  String get csvImportEmpty =>
      'Diese CSV enthält keine Ausgaben oder Zahlungen.';

  @override
  String importedExpensesAndPayments(String expenses, String payments) {
    return '$expenses und $payments importiert';
  }

  @override
  String recordAddedBy(String name) {
    return 'Hinzugefügt von $name';
  }

  @override
  String recordEditedBy(String name) {
    return 'Zuletzt bearbeitet von $name';
  }

  @override
  String recordRecordedBy(String name) {
    return 'Erfasst von $name';
  }

  @override
  String get recordYou => 'dir';

  @override
  String get recordUnsigned =>
      'Von einer älteren App-Version gespeichert (unsigniert)';

  @override
  String get recordSigUnverified =>
      'Nicht überprüfbar – das Gerät, das ihn geschrieben hat, ist evtl. abgemeldet';

  @override
  String get recordSigVerified =>
      'Beim Empfang geprüft: stammt von diesem Gerät';

  @override
  String recordSigVouched(String name) {
    return 'Gerät bestätigt von $name';
  }

  @override
  String recordSigConflict(String name) {
    return 'Signatur passt nicht zum Gerät von $name';
  }

  @override
  String get recordNotYourDevice =>
      'Gibt vor, von dir zu sein – aber nicht von einem deiner Geräte';

  @override
  String recordVersionRejected(String relay, String name) {
    return 'Eine neuere Version (weitergeleitet von $relay) wurde abgelehnt: Sie gibt vor, von $name zu sein, ist aber nicht gültig von dessen Gerät signiert.';
  }

  @override
  String recordSignedByDevice(String device, String date) {
    return 'Signiert von Gerät $device · $date';
  }

  @override
  String get recordSignatureDetails => 'Signaturdetails';

  @override
  String get recordSignatureWarning => 'Signaturproblem';

  @override
  String peerHasNoVerifiedDevice(Object peer) {
    return '$peer hat kein verifiziertes Gerät – verifiziere eines, um mit der Person zu synchronisieren';
  }

  @override
  String get verifiedOnlyTitle =>
      'Nur mit verifizierten Geräten synchronisieren';

  @override
  String get verifiedOnlyOffBody =>
      'Aus: Alle Geräte der Personen in deinen Gruppen (und deine eigenen) bekommen deine Daten.';

  @override
  String get verifiedOnlyOnBody =>
      'An: Dieses Gerät sendet nur an Geräte, die du verifiziert hast – das gilt auch für eine neue Anmeldung von dir. Andere Geräte synchronisieren weiter untereinander.';

  @override
  String get verifiedOnlyConfirmTitle =>
      'Nur mit verifizierten Geräten synchronisieren?';

  @override
  String get verifiedOnlyConfirmBody =>
      'Dieses Gerät schickt deine Änderungen dann nur noch an Geräte, die du per Emoji-Vergleich verifiziert hast. Nicht verifizierte Geräte – auch das neue Handy einer Person oder eine neue Anmeldung von dir – bekommen von hier nichts, bis du sie verifizierst. Das betrifft nur, was dieses Gerät sendet: Andere Geräte synchronisieren weiter untereinander.';

  @override
  String get verifiedOnlyTurnOn => 'Einschalten';

  @override
  String memberUnverifiedDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nicht verifizierte Geräte',
      one: '1 nicht verifiziertes Gerät',
    );
    return '$_temp0';
  }

  @override
  String get memberNotReachableUnverified =>
      'Nicht erreichbar – kein verifiziertes Gerät';

  @override
  String memberDevicesTitle(Object name) {
    return 'Geräte von $name';
  }

  @override
  String get memberDevicesBody =>
      'Verifiziere ein Gerät, indem du mit der Person Emojis vergleichst (persönlich oder per Anruf). Die Verifizierung wird nur auf diesem Gerät gespeichert.';

  @override
  String get memberHasNoDevices => 'Keine aktiven Geräte.';

  @override
  String get incomingVerificationTitle => 'Verifizierungsanfrage';

  @override
  String incomingVerificationOwnDevice(Object device) {
    return 'Dein Gerät $device möchte dieses Gerät per Emoji-Vergleich verifizieren.';
  }

  @override
  String incomingVerificationMember(Object user, Object device) {
    return '$user (Gerät $device) möchte dieses Gerät per Emoji-Vergleich verifizieren.';
  }

  @override
  String get accept => 'Annehmen';

  @override
  String get decline => 'Ablehnen';

  @override
  String get recordDeviceVerifiedByYou => 'Du hast dieses Gerät verifiziert.';

  @override
  String get recordDeviceNotVerifiedByYou =>
      'Du hast dieses Gerät nicht verifiziert.';

  @override
  String get categoryLabel => 'Kategorie';

  @override
  String get categoryFood => 'Essen & Trinken';

  @override
  String get categoryGroceries => 'Lebensmittel';

  @override
  String get categoryTransport => 'Verkehr';

  @override
  String get categoryAccommodation => 'Unterkunft';

  @override
  String get categoryEntertainment => 'Freizeit';

  @override
  String get categoryShopping => 'Shopping';

  @override
  String get categoryHome => 'Wohnen & Nebenkosten';

  @override
  String get categoryHealth => 'Gesundheit';

  @override
  String get categoryTravel => 'Reisen';

  @override
  String get categoryOther => 'Sonstiges';

  @override
  String get noteLabel => 'Notiz (optional)';

  @override
  String get expenseHasNote => 'Hat eine Notiz';

  @override
  String get recordNotSyncedYet => 'Noch nicht synchronisiert';

  @override
  String get searchTooltip => 'Suchen';

  @override
  String get searchHint => 'Beschreibung, Notiz, Zahler suchen';

  @override
  String get closeSearch => 'Suche schließen';

  @override
  String get filterInvolvingMe => 'Betrifft mich';

  @override
  String get noMatchesTitle => 'Nichts gefunden';

  @override
  String get noMatchesBody =>
      'Versuch eine andere Suche oder setz die Filter zurück.';

  @override
  String get clearFilters => 'Filter zurücksetzen';

  @override
  String filterResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
    );
    return '$_temp0';
  }

  @override
  String get archiveGroup => 'Gruppe archivieren';

  @override
  String get unarchiveGroup => 'Aus dem Archiv holen';

  @override
  String archivedSection(int count) {
    return 'Archiviert ($count)';
  }

  @override
  String get archivedSectionHint =>
      'Nur auf diesem Gerät ausgeblendet. Eine Gruppe kommt von selbst zurück, sobald etwas Neues hinzukommt.';

  @override
  String groupArchived(String name) {
    return '„$name“ archiviert';
  }

  @override
  String groupArchivedUnsettled(String name) {
    return '„$name“ archiviert – dein offener Saldo zählt weiter in der Übersicht.';
  }

  @override
  String groupUnarchived(String name) {
    return '„$name“ ist wieder bei deinen Gruppen';
  }

  @override
  String get archivedBanner => 'Diese Gruppe ist auf diesem Gerät archiviert.';

  @override
  String get undo => 'Rückgängig';

  @override
  String get simplifyDebtsInfoTooltip => 'Wie entstehen die Vorschläge?';

  @override
  String get simplifyDebtsInfoTitle => 'Vereinfachte Schulden';

  @override
  String get simplifyDebtsInfoBody =>
      'MoneyLedger verrechnet alle Ausgaben und Zahlungen zu einem Saldo pro Person und schlägt die wenigsten Zahlungen vor, mit denen alle ausgeglichen sind. Dabei kann es sein, dass du jemandem Geld gibst, mit dem du nie direkt eine Ausgabe geteilt hast – was jede Person insgesamt zahlt und zurückbekommt, bleibt genau gleich.\n\nJede Währung wird für sich ausgeglichen: Beträge werden nie umgerechnet.';

  @override
  String get simplifyDebtsPerCurrency =>
      'Jede Währung wird separat ausgeglichen – Beträge werden nie umgerechnet.';

  @override
  String get backupPassphraseTitle => 'Sicherung schützen?';

  @override
  String get backupPassphraseBody =>
      'Du kannst die Datei mit einer Passphrase verschlüsseln. Lass das Feld leer, um sie unverschlüsselt zu speichern.';

  @override
  String get backupPassphraseLabel => 'Passphrase (optional)';

  @override
  String get backupPassphraseConfirmLabel => 'Passphrase wiederholen';

  @override
  String get backupPassphraseMismatch =>
      'Die Passphrasen stimmen nicht überein';

  @override
  String get backupPassphraseWeak =>
      'Stärke: schwach – nimm eine längere, z. B. vier zufällige Wörter';

  @override
  String get backupPassphraseFair => 'Stärke: mittel';

  @override
  String get backupPassphraseStrong => 'Stärke: stark';

  @override
  String get backupPlaintextWarning =>
      'Ohne Passphrase ist die Datei nicht verschlüsselt: Wer sie bekommt, kann alle Gruppen darin lesen.';

  @override
  String get backupPassphraseKeepSafe =>
      'Verliere die Passphrase nicht – ohne sie lässt sich die Sicherung nicht wiederherstellen, und niemand kann sie zurückholen.';

  @override
  String get backupEncrypting => 'Verschlüssele …';

  @override
  String get backupDecrypting => 'Entschlüssele …';

  @override
  String get backupUnlockTitle => 'Verschlüsselte Sicherung';

  @override
  String get backupUnlockBody =>
      'Gib die Passphrase ein, mit der diese Sicherung gespeichert wurde.';

  @override
  String get backupUnlockLabel => 'Passphrase';

  @override
  String get backupUnlockAction => 'Entsperren';

  @override
  String get backupWrongPassphrase =>
      'Falsche Passphrase – oder die Datei wurde verändert. Versuch es noch einmal.';

  @override
  String get backupSavedNoName => 'Sicherung gespeichert';

  @override
  String backupSavedEncrypted(String fileName) {
    return 'Verschlüsselte Sicherung gespeichert: $fileName';
  }

  @override
  String get backupSavedEncryptedNoName =>
      'Verschlüsselte Sicherung gespeichert';

  @override
  String get exportedNoName => 'CSV exportiert';

  @override
  String get backupThisGroup => 'Diese Gruppe sichern';

  @override
  String get showPassphrase => 'Passphrase anzeigen';

  @override
  String get hidePassphrase => 'Passphrase verbergen';

  @override
  String get restoreEncryptedNote =>
      'Verschlüsselte Sicherung – mit deiner Passphrase entsperrt.';

  @override
  String get restoreTagRemoved => 'schreibgeschützt – du wurdest entfernt';

  @override
  String restoreIncomplete(int count, String error) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Gruppen konnten nicht wiederhergestellt werden und blieben unverändert: $error',
      one:
          '1 Gruppe konnte nicht wiederhergestellt werden und blieb unverändert: $error',
    );
    return '$_temp0';
  }

  @override
  String get legacyRefusedTitle =>
      'Einige Daten konnten nicht empfangen werden';

  @override
  String legacyRefusedBody(int count, String sender, String group) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$sender hat $count Einträge von „$group“ geschickt, die mit einer älteren App-Version ohne Signatur gespeichert wurden. Sie wurden abgelehnt – die Gruppe ist hier deshalb unvollständig oder fehlt. Bitte $sender, die Gruppe neu anzulegen.',
      one:
          '$sender hat 1 Eintrag von „$group“ geschickt, der mit einer älteren App-Version ohne Signatur gespeichert wurde. Er wurde abgelehnt – die Gruppe ist hier deshalb unvollständig oder fehlt. Bitte $sender, die Gruppe neu anzulegen.',
    );
    return '$_temp0';
  }

  @override
  String get debugRunBackgroundSync =>
      'Hintergrund-Synchronisierung jetzt ausführen (Debug)';

  @override
  String debugRunBackgroundSyncBody(int seconds) {
    return 'Plant eine Hintergrundrunde in $seconds s ein – schließe die App, um sie ohne App zu testen.';
  }

  @override
  String get debugRunBackgroundSyncQueued => 'Hintergrundrunde eingeplant.';

  @override
  String get authInProgressTitle => 'Die Anmeldung läuft noch …';

  @override
  String get authInProgressHint =>
      'Der vorherige Versuch wartet noch auf den Server. Klappt er, wirst du automatisch angemeldet – sonst versuche es gleich noch einmal.';

  @override
  String inviteWhoIs(Object userId) {
    return 'Wer ist $userId in dieser Gruppe?';
  }

  @override
  String get inviteAsNewParticipant => 'Eine neue Person';

  @override
  String amountPreview(Object amount) {
    return '= $amount';
  }

  @override
  String get amountMustBePositive => 'Gib einen Betrag größer als 0 ein';

  @override
  String get amountTooLarge => 'Dieser Betrag ist zu groß';

  @override
  String get finishingBackgroundSync =>
      'Hintergrund-Synchronisierung wird abgeschlossen …';

  @override
  String csvImportInvalidRow(int row, Object problem) {
    return 'Zeile $row: $problem';
  }

  @override
  String get welcomeSkip => 'Überspringen';

  @override
  String get welcomeNext => 'Weiter';

  @override
  String get welcomeBack => 'Zurück';

  @override
  String get welcomeDone => 'Fertig';

  @override
  String welcomePageOf(int page, int count) {
    return 'Seite $page von $count';
  }

  @override
  String get welcomeIntroTitle => 'Ausgaben fair teilen';

  @override
  String get welcomeIntroBody =>
      'MoneyLedger hält fest, wer in einer Gruppe was bezahlt hat – auf einer Reise, in der WG, beim Essen – und zeigt, wer wem etwas schuldet, wie Splitwise oder Tricount. Teile gleichmäßig oder ungleich auf, erfasse Zahlungen und gleiche Schulden aus.';

  @override
  String get welcomeOpenTitle => 'Kostenlos, Open Source, ohne Server';

  @override
  String get welcomeOpenBody =>
      'MoneyLedger ist freie Software (AGPL-3.0-or-later) – jede und jeder kann den Quellcode lesen. Es gibt keinen MoneyLedger-Server und kein MoneyLedger-Konto: Deine Gruppen und Ausgaben liegen nur auf deinen Geräten.';

  @override
  String get welcomeSourceLink => 'Quellcode ansehen';

  @override
  String get welcomeMatrixTitle => 'Was ist Matrix?';

  @override
  String get welcomePrivacyServer =>
      'Homeserver leiten nur verschlüsselte Nachrichten weiter: Sie sehen, welche Konten wann Nachrichten austauschen, nie deren Inhalt, und behalten nach der Zustellung nichts.';

  @override
  String get welcomePrivacyNothingElse =>
      'Sonst nichts: kein MoneyLedger-Server, kein Tracking, keine Werbung.';

  @override
  String get welcomeStartTitle => 'Wie möchtest du starten?';

  @override
  String get welcomeStartBody =>
      'Leg direkt los – ohne Konto. Teile eine Gruppe mit einem Einladungslink, wann immer du willst.';

  @override
  String get welcomeSignIn => 'Mit Matrix anmelden';

  @override
  String get welcomeCreateAccount => 'Matrix-Konto erstellen';

  @override
  String get welcomeUseLocal => 'Ohne Konto starten';

  @override
  String get welcomeUseLocalHint =>
      'Gruppen, die du nicht teilst, bleiben auf diesem Gerät. Du kannst später ein Matrix-Konto verbinden – deine Gruppen kommen mit.';

  @override
  String get howItWorksTitle => 'So funktioniert MoneyLedger';

  @override
  String get localSetupStaysHere =>
      'Gruppen, die du nicht teilst, bleiben nur auf diesem Gerät – nichts wird irgendwohin gesendet.';

  @override
  String get localSetupPeople => 'Füge die anderen Personen mit Namen hinzu.';

  @override
  String get localSetupBackup =>
      'Sichere regelmäßig: Geht das Gerät verloren oder wird es zurückgesetzt, sind die Daten weg.';

  @override
  String get localSetupConnectLater =>
      'Teile eine Gruppe mit einem Einladungslink – die anderen machen ohne Konto mit. Ein Matrix-Konto (sicherer Modus) kannst du später verbinden.';

  @override
  String localSetupAdoptedNotice(Object account) {
    return 'Deine früheren lokalen Gruppen wurden beim Verbinden in $account übernommen – melde dich mit diesem Konto an, um sie zu sehen. Der lokale Modus startet leer.';
  }

  @override
  String get localSetupNameLabel => 'Dein Name';

  @override
  String get localSetupNameHelper => 'So erscheinst du in deinen Gruppen';

  @override
  String get localSetupNameRequired => 'Gib einen Namen ein';

  @override
  String get localSetupStart => 'Los geht\'s';

  @override
  String get localModeChip => 'Kein Konto';

  @override
  String get localModeSheetTitle => 'Ohne Konto';

  @override
  String get localModeSheetBody =>
      'Du nutzt MoneyLedger ohne Konto. Gruppen, die du nicht mit einem Einladungslink teilst, verlassen dieses Gerät nie: Sie werden nicht synchronisiert, und die anderen Personen sind nur Namen in deinen Gruppen.';

  @override
  String get localModeBackupHint =>
      'Sichere regelmäßig (Einstellungen → Sichern & Wiederherstellen) – niemand sonst hat eine Kopie.';

  @override
  String get localModeConnectHint =>
      'Verbinde ein Matrix-Konto (sicherer Modus), um deine Geräte zu synchronisieren und Personen über ihre Matrix-ID einzuladen. Deine Gruppen ziehen in dieses Konto um; per Link geteilte Gruppen behalten ihren Link und werden zusätzlich über Matrix synchronisiert.';

  @override
  String get localModeSettingsBody =>
      'Kein Konto – Gruppen, die du nicht teilst, bleiben auf diesem Gerät.';

  @override
  String localProfileName(Object name) {
    return 'Dein Name: $name';
  }

  @override
  String get localProfileNameHint =>
      'Gilt für neue Gruppen – in einer Gruppe benennst du dich auf ihrer Seite „Personen“ um';

  @override
  String get connectMatrixAccount => 'Matrix-Konto verbinden';

  @override
  String get connectMatrixAccountBody =>
      'Teile deine Gruppen und synchronisiere deine Geräte – deine lokalen Daten ziehen in das Konto um';

  @override
  String get connectSignInSubtitle =>
      'Melde dich an – deine lokalen Gruppen ziehen dann in dieses Matrix-Konto um';

  @override
  String get deleteLocalData => 'Lokale Daten löschen';

  @override
  String get deleteLocalDataBody =>
      'Entfernt alle Gruppen von diesem Gerät und beendet den lokalen Modus';

  @override
  String get deleteLocalDataConfirmTitle => 'Alle lokalen Daten löschen?';

  @override
  String deleteLocalDataConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Alle $count Gruppen werden mit ihren Ausgaben und Zahlungen von diesem Gerät gelöscht.',
      one:
          'Die Gruppe wird mit allen Ausgaben und Zahlungen von diesem Gerät gelöscht.',
      zero: 'Der lokale Modus wird beendet.',
    );
    return '$_temp0 Ohne Sicherung gibt es keine andere Kopie. Das lässt sich nicht rückgängig machen.';
  }

  @override
  String get deleteLocalDataConfirmAction => 'Alles löschen';

  @override
  String get localModeYouSubtitle => 'Du (auf diesem Gerät)';

  @override
  String get localModeMembersHint =>
      'Ohne Konto: Personen werden mit Namen hinzugefügt. Lade sie über das Gruppenmenü mit einem Link ein oder verbinde ein Matrix-Konto (Einstellungen).';

  @override
  String localAdoptedBanner(int count, Object account) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deine $count lokalen Gruppen gehören jetzt zu $account.',
      one: 'Deine lokale Gruppe gehört jetzt zu $account.',
    );
    return '$_temp0 Du kannst Personen über ihre Matrix-ID einladen.';
  }

  @override
  String get onboardingReadyTitle => 'Alles bereit';

  @override
  String get onboardingReadyBody =>
      'Ein paar Dinge, die du jetzt nach der Anmeldung wissen solltest.';

  @override
  String get onboardingReadyLocalBody =>
      'Ein paar Dinge, die du vor dem Start wissen solltest.';

  @override
  String get onboardingBackgroundTitle => 'Synchronisiert auch im Hintergrund';

  @override
  String get onboardingBackgroundBody =>
      'Die Geräte in einer Gruppe tauschen Änderungen aus, solange die App läuft – unter Android auch etwa alle 15 Minuten im Hintergrund (Einstellungen).';

  @override
  String get onboardingLocalOnlyTitle => 'Kein Konto nötig';

  @override
  String get onboardingLocalOnlyBody =>
      'Lege Gruppen an und füge die anderen Personen mit Namen hinzu. Gruppen, die du nicht teilst, bleiben nur auf diesem Gerät.';

  @override
  String get onboardingBackupLocalBody =>
      'Niemand sonst hat eine Kopie deiner Daten. Speichere ab und zu eine Sicherung (Einstellungen → Sichern & Wiederherstellen) und bewahre sie sicher auf.';

  @override
  String get onboardingBackupLinkBody =>
      'Alle mit dem Einladungslink haben eine Kopie einer geteilten Gruppe – und können sie ändern oder leeren. Speichere ab und zu eine Sicherung (Einstellungen → Sichern & Wiederherstellen) und bewahre sie sicher auf.';

  @override
  String get privacyLocalTitle => 'Lokaler Modus (ohne Konto)';

  @override
  String get privacyLocalBody =>
      'Wenn du MoneyLedger ohne Matrix-Konto nutzt, senden Gruppen, die du nicht teilst, nichts: Für sie kontaktiert die App keinen Server und synchronisiert nichts (die Web-Version wird nur von der Seite geladen, auf der sie bereitgestellt wird). Eine Gruppe, die du mit einem Einladungslink teilst, synchronisiert über öffentliche Nostr-Relays (siehe „Geteilte Gruppen (Einladungslink)“). Links, auf die du tippst – etwa zum Quellcode –, öffnen sich in deinem Browser; „Aktuellen Kurs abrufen“ fragt den Wechselkurs-Dienst nur, wenn du darauf tippst (siehe „Wechselkurse“). Dein Name, deine Gruppen, Ausgaben und Zahlungen liegen nur in einer lokalen Datenbank auf diesem Gerät, dazu eine kleine Einstellungsdatei (ob du die Begrüßung gesehen hast, dein lokaler Profilname). „Lokale Daten löschen“ in den Einstellungen oder das Deinstallieren der App entfernt sie. Verbindest du später ein Matrix-Konto, ziehen die lokalen Daten in dieses Konto um, und ab dann gelten die Abschnitte oben.';

  @override
  String get categoryNone => 'Keine Kategorie';

  @override
  String get newCategoryEntry => 'Neue Kategorie …';

  @override
  String get newCategoryTitle => 'Neue Kategorie';

  @override
  String get editCategoryTitle => 'Kategorie bearbeiten';

  @override
  String get categoryNameLabel => 'Name';

  @override
  String get categoryIconLabel => 'Symbol';

  @override
  String categoryNameTooLong(int max) {
    return 'Höchstens $max Zeichen';
  }

  @override
  String get categoryNameTaken =>
      'Diese Gruppe hat schon eine Kategorie mit diesem Namen';

  @override
  String get manageCategories => 'Kategorien';

  @override
  String get customCategoriesHint =>
      'Eigene Kategorien sehen alle in dieser Gruppe. Ausgeblendete werden für neue Ausgaben nicht mehr angeboten, bleiben aber an älteren stehen.';

  @override
  String get noCustomCategories => 'Noch keine eigenen Kategorien.';

  @override
  String get hideCategory => 'Ausblenden';

  @override
  String get showCategory => 'Wieder einblenden';

  @override
  String get categoryHidden => 'Ausgeblendet';

  @override
  String categoryLimitReached(int max) {
    return 'Eine Gruppe kann höchstens $max eigene Kategorien haben.';
  }

  @override
  String get builtInCategories => 'Standard';

  @override
  String get groupCategories => 'Diese Gruppe';

  @override
  String get restorePointsTitle => 'Wiederherstellungspunkte';

  @override
  String get restorePointsTileBody =>
      'Einen Tag auswählen und wiederherstellen';

  @override
  String get restorePointsIntro =>
      'Einmal am Tag, wenn sich etwas geändert hat, legt MoneyLedger eine Kopie all deiner Gruppen auf diesem Gerät ab – die letzten 7 Tage und 4 ältere Wochen. Diese Kopien verlassen dein Gerät nie.';

  @override
  String get restorePointsHowItWorks =>
      'Wiederherstellen holt Gruppen und Einträge zurück, die hier fehlen (z. B. eine gelöschte Gruppe). Mit „Genau diesen Stand“ werden auch spätere Änderungen in diesen Gruppen rückgängig gemacht. Um Änderungen in einer einzelnen Gruppe rückgängig zu machen: Gruppe öffnen → Gruppeneinstellungen → Auf früheren Stand zurücksetzen.';

  @override
  String get restorePointsEmpty =>
      'Noch keine Wiederherstellungspunkte. Einmal am Tag wird einer angelegt, wenn sich etwas geändert hat.';

  @override
  String get restorePointsWebUnsupported =>
      'Die Browser-Version legt keine automatischen Kopien an. Du kannst eine Gruppe trotzdem auf einen früheren Stand zurücksetzen (Gruppe → Gruppeneinstellungen) und eine Sicherungsdatei speichern.';

  @override
  String restorePointGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Gruppen',
      one: '1 Gruppe',
    );
    return '$_temp0';
  }

  @override
  String restorePointEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
    );
    return '$_temp0';
  }

  @override
  String get restorePointRestore => 'Wiederherstellen';

  @override
  String get groupResetMenu => 'Auf früheren Stand zurücksetzen …';

  @override
  String get groupResetTitle => 'Gruppe zurücksetzen';

  @override
  String get groupResetIntro =>
      'Wähle eine Änderung, um sie und alles danach rückgängig zu machen. Ausgaben, Zahlungen und die Gruppeneinstellungen gehen auf den Stand zurück, den sie davor auf diesem Gerät hatten. Personen bleiben, wie sie sind. Alle in der Gruppe bekommen das Ergebnis als normale Änderung – und du kannst ein Zurücksetzen genauso wieder rückgängig machen.';

  @override
  String get groupResetLocalIntro =>
      'Wähle eine Änderung, um sie und alles danach rückgängig zu machen. Ausgaben, Zahlungen und die Gruppeneinstellungen gehen auf den Stand davor zurück. Personen bleiben, wie sie sind. Du kannst ein Zurücksetzen genauso wieder rückgängig machen.';

  @override
  String get groupResetRetention =>
      'Änderungen werden 90 Tage auf diesem Gerät aufbewahrt.';

  @override
  String get groupResetEmpty =>
      'Noch nichts, wohin du zurück kannst – Änderungen erscheinen hier, sobald sie passieren.';

  @override
  String get groupResetReadOnly =>
      'Du wurdest aus dieser Gruppe entfernt, deshalb kann sie nicht zurückgesetzt werden.';

  @override
  String changeAdded(int count) {
    return '$count hinzugefügt';
  }

  @override
  String changeEdited(int count) {
    return '$count geändert';
  }

  @override
  String changeDeleted(int count) {
    return '$count gelöscht';
  }

  @override
  String changeOther(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen an Gruppe oder Personen',
      one: '1 Änderung an Gruppe oder Personen',
    );
    return '$_temp0';
  }

  @override
  String get changeByYou => 'von dir';

  @override
  String changeBy(String names) {
    return 'von $names';
  }

  @override
  String get changeUndoFromHere => 'Ab hier rückgängig';

  @override
  String get changeEarliest => 'Ältester Stand auf diesem Gerät';

  @override
  String resetPreviewTitle(String time) {
    return 'Auf den Stand vor $time zurück?';
  }

  @override
  String resetPreviewRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge kommen zurück',
      one: '1 Eintrag kommt zurück',
    );
    return '$_temp0';
  }

  @override
  String resetPreviewReverted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen werden rückgängig gemacht',
      one: '1 Änderung wird rückgängig gemacht',
    );
    return '$_temp0';
  }

  @override
  String resetPreviewRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge werden entfernt',
      one: '1 Eintrag wird entfernt',
    );
    return '$_temp0';
  }

  @override
  String get resetPreviewMeta =>
      'Gruppenname, Währung und Kategorien gehen ebenfalls zurück.';

  @override
  String resetPreviewSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count frühere Versionen lassen sich nicht wiederherstellen; die Einträge bleiben, wie sie sind.',
      one:
          '1 frühere Version lässt sich nicht wiederherstellen; der Eintrag bleibt, wie er ist.',
    );
    return '$_temp0';
  }

  @override
  String get resetPreviewNothing =>
      'Nichts zu ändern – die Gruppe sieht schon so aus.';

  @override
  String get resetPreviewShared =>
      'Alle in der Gruppe bekommen diese Änderungen.';

  @override
  String resetPreviewMore(int count) {
    return '… und $count weitere';
  }

  @override
  String get resetEffectRestored => 'kommt zurück';

  @override
  String get resetEffectReverted => 'wird zurückgeändert';

  @override
  String get resetEffectRemoved => 'wird entfernt';

  @override
  String get resetConfirm => 'Zurücksetzen';

  @override
  String resetDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Gruppe zurückgesetzt ($count Änderungen)',
      one: 'Gruppe zurückgesetzt (1 Änderung)',
    );
    return '$_temp0';
  }

  @override
  String get privacyRestorePointsTitle =>
      'Wiederherstellungspunkte auf diesem Gerät';

  @override
  String get privacyRestorePointsBody =>
      'Damit du Fehler rückgängig machen kannst, bewahrt MoneyLedger frühere Versionen der Einträge deiner Gruppen 90 Tage lang auf diesem Gerät auf, und unter Android einmal am Tag (wenn sich etwas geändert hat) eine Kopie all deiner Gruppen im privaten Speicher der App – die letzten 7 Tage und 4 ältere Wochen. Diese Versionen und Kopien werden nie irgendwohin gesendet, sind in keiner Sicherungsdatei enthalten und wie alle App-Daten von den Android-Backups ausgenommen. Wenn du eine Gruppe verlässt oder löschst, werden ihre früheren Versionen sofort entfernt; die täglichen Kopien enthalten sie noch, bis sie herausrotiert sind (nach etwa fünf Wochen), damit eine versehentlich gelöschte Gruppe wiederhergestellt werden kann. „Lokale Daten löschen“ oder das Deinstallieren der App entfernt alles.';

  @override
  String get expenseDateLabel => 'Datum';

  @override
  String get expenseDatePickerHelp => 'Wann war das?';

  @override
  String get copy => 'Kopieren';

  @override
  String get copiedToClipboard => 'Kopiert';

  @override
  String get devicesSettingsBody =>
      'Wo du angemeldet bist; Geräte per Emoji-Vergleich prüfen';

  @override
  String get addPeopleHint => 'Bisher bist nur du in dieser Gruppe.';

  @override
  String get dismiss => 'Ausblenden';

  @override
  String get discardChangesTitle => 'Änderungen verwerfen?';

  @override
  String get discardChangesBody =>
      'Was du für diese Ausgabe eingegeben hast, geht verloren.';

  @override
  String get discard => 'Verwerfen';

  @override
  String get keepEditing => 'Weiter bearbeiten';

  @override
  String get restoreExactTitle => 'Genau diesen Stand';

  @override
  String get restoreExactSubtitle =>
      'Auch spätere Änderungen rückgängig machen: Bearbeitungen werden zurückgesetzt, neuere Einträge entfernt, gelöschte kommen zurück. Personen bleiben, wie sie sind.';

  @override
  String get restoreExactWarning =>
      'Neuere Änderungen in diesen Gruppen – auch die anderer Personen – werden für alle in der Gruppe überschrieben.';

  @override
  String get restoreExactWarningLocal =>
      'Neuere Änderungen in diesen Gruppen werden überschrieben.';

  @override
  String get restoreExactTagMeta => 'Gruppeneinstellungen';

  @override
  String get restoreTagMergeOnly => 'nur fehlende Einträge';

  @override
  String restoreExactDone(int groups, int changes) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups Gruppen wiederhergestellt',
      one: '1 Gruppe wiederhergestellt',
    );
    String _temp1 = intl.Intl.pluralLogic(
      changes,
      locale: localeName,
      other: '$changes Änderungen',
      one: '1 Änderung',
    );
    return '$_temp0 ($_temp1)';
  }

  @override
  String get createGroupPeopleLabel => 'Wer ist dabei?';

  @override
  String get createGroupPeopleHelper =>
      'Füge die Personen hinzu, mit denen du Kosten teilst – Enter fügt die nächste hinzu. Weitere kannst du später hinzufügen.';

  @override
  String removePersonTooltip(String name) {
    return '$name entfernen';
  }

  @override
  String duplicatePersonHint(String name) {
    return 'In dieser Gruppe gibt es schon $name. Du kannst die Person trotzdem hinzufügen – ein eindeutiger Name (z. B. „$name B.“) hilft, sie auseinanderzuhalten.';
  }

  @override
  String get addAndNext => 'Hinzufügen & weitere';

  @override
  String removeMemberGetsBack(String name, String amount) {
    return '$name bekommt noch $amount zurück.';
  }

  @override
  String removeMemberOwes(String name, String amount) {
    return '$name schuldet noch $amount.';
  }

  @override
  String get removeMemberBalanceNote =>
      'Entfernen ändert den Saldo nicht: Er bleibt in den Ausgleichsvorschlägen, bis er ausgeglichen ist.';

  @override
  String get settleUpFirst => 'Erst ausgleichen';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsSectionAccount => 'Konto';

  @override
  String get settingsSectionSync => 'Synchronisierung';

  @override
  String get settingsSectionBackup => 'Sichern & Wiederherstellen';

  @override
  String get settingsSectionData => 'Daten';

  @override
  String get settingsSectionAbout => 'Info';

  @override
  String get settingsSectionDebug => 'Debug';

  @override
  String get settingsMatrixAccount => 'Matrix-Konto';

  @override
  String get signOutTileBody =>
      'Deine Gruppen bleiben für die nächste Anmeldung auf diesem Gerät.';

  @override
  String get importCsvTileBody =>
      'Eine Gruppe aus einer CSV-Datei übernehmen, z. B. aus einem Export.';

  @override
  String get groupSettingsTitle => 'Gruppeneinstellungen';

  @override
  String get groupSectionGroup => 'Gruppe';

  @override
  String get groupSectionDevice => 'Auf diesem Gerät';

  @override
  String get groupSectionExit => 'Verlassen oder löschen';

  @override
  String get groupNameAndCurrency => 'Name & Währung';

  @override
  String groupNameCurrencyValue(String name, String currency) {
    return '$name · $currency';
  }

  @override
  String get categoriesTileBody => 'Eigene Kategorien dieser Gruppe';

  @override
  String get exportCsvTileBody => 'Eine Tabelle mit den Ausgaben und Zahlungen';

  @override
  String get backupGroupTileBody =>
      'Eine Sicherungsdatei nur mit dieser Gruppe';

  @override
  String get groupResetTileBody =>
      'Änderungen ab einem Zeitpunkt rückgängig machen';

  @override
  String get archiveTileBody =>
      'Verschiebt sie in deiner Liste nach „Archiviert“. Nur hier – die anderen merken nichts.';

  @override
  String get unarchiveTileBody => 'Zurück in deine Gruppenliste';

  @override
  String get leaveGroupTileBody =>
      'Entfernt die Gruppe von diesem Gerät. Die anderen sehen, dass du gegangen bist.';

  @override
  String get deleteGroupTileBody =>
      'Entfernt die Gruppe mit allen Einträgen von diesem Gerät.';

  @override
  String get chooseCurrencyTitle => 'Währung wählen';

  @override
  String get currencySearchHint => 'Code oder Name suchen';

  @override
  String get currencySuggested => 'Vorschläge';

  @override
  String get currencyAll => 'Alle Währungen';

  @override
  String get currencyNoMatch => 'Keine Währung gefunden';

  @override
  String expenseDeletedSnack(String description) {
    return '„$description“ gelöscht';
  }

  @override
  String get paymentDeletedSnack => 'Zahlung gelöscht';

  @override
  String expenseAddedSnack(String description) {
    return '„$description“ hinzugefügt';
  }

  @override
  String expenseUpdatedSnack(String description) {
    return '„$description“ gespeichert';
  }

  @override
  String get undoDone => 'Rückgängig gemacht';

  @override
  String get undoChangedMeanwhile =>
      'Rückgängig nicht möglich – der Eintrag wurde inzwischen geändert. Es wurde nichts verändert.';

  @override
  String get deletePayment => 'Zahlung löschen';

  @override
  String get deleteExpenseAction => 'Ausgabe löschen';

  @override
  String get expenseDetailsTitle => 'Ausgabe';

  @override
  String get paymentDetailsTitle => 'Zahlung';

  @override
  String get detailsReadOnlyHint =>
      'Du kannst das nur ansehen – du gehörst nicht mehr zu dieser Gruppe.';

  @override
  String get detailsSplitHeading => 'Aufteilung';

  @override
  String get detailsNoteHeading => 'Notiz';

  @override
  String get detailsDateHeading => 'Datum';

  @override
  String get detailsCategoryHeading => 'Kategorie';

  @override
  String get errorDetails => 'Details';

  @override
  String get errorDetailsTitle => 'Fehlerdetails';

  @override
  String get errorInterruptedTitle => 'Das hat nicht geklappt';

  @override
  String get errorInterruptedHint =>
      'Die App hat gerade das Konto gewechselt oder die Daten geschlossen. Bitte versuch es noch einmal.';

  @override
  String get errorRelayTitle => 'Dein Matrix-Konto ist gerade nicht erreichbar';

  @override
  String get errorRelayHint =>
      'Vielleicht bist du abgemeldet oder die Verschlüsselung ist noch nicht bereit. Versuch es gleich noch einmal.';

  @override
  String get errorRecordGoneTitle => 'Dieser Eintrag wurde inzwischen gelöscht';

  @override
  String get errorRecordGoneHint => 'Es wurde nichts geändert.';

  @override
  String get errorTooLargeTitle => 'Zu viele Daten für eine Nachricht';

  @override
  String get errorTooLargeHint =>
      'Diese Gruppe ist zu groß, um sie auf einmal zu senden. Bitte melde dieses Problem.';

  @override
  String get errorLinkOnlyTitle => 'In einer Link-Gruppe nicht möglich';

  @override
  String get errorLinkOnlyHint =>
      'Eine per Link geteilte Gruppe kann keine Matrix-IDs haben.';

  @override
  String get errorFileTitle =>
      'Die Datei konnte nicht gelesen oder geschrieben werden';

  @override
  String get errorFileHint =>
      'Prüfe, ob der Speicherort beschreibbar ist und genug Platz frei ist.';

  @override
  String get errorStorageTitle => 'Speichern auf diesem Gerät fehlgeschlagen';

  @override
  String get errorStorageHint =>
      'Der Gerätespeicher hat einen Fehler gemeldet. Schaffe etwas Platz und versuch es noch einmal.';

  @override
  String get errorTimeoutTitle => 'Das hat zu lange gedauert';

  @override
  String get errorTimeoutHint =>
      'Prüfe deine Verbindung und versuch es noch einmal.';

  @override
  String get errorNetworkTitle => 'Keine Verbindung';

  @override
  String get errorNetworkHint =>
      'Prüfe deine Internetverbindung und versuch es noch einmal.';

  @override
  String get errorInvalidDataTitle => 'Die Daten konnten nicht gelesen werden';

  @override
  String get errorInvalidDataHint =>
      'Sie scheinen beschädigt zu sein oder haben ein unerwartetes Format.';

  @override
  String get errorUnknownTitle => 'Etwas ist schiefgelaufen';

  @override
  String get errorUnknownHint =>
      'Bitte versuch es noch einmal. Die Details helfen, wenn du das Problem meldest.';

  @override
  String get exportFailedTitle => 'Export fehlgeschlagen';

  @override
  String get importFailedTitle => 'Import fehlgeschlagen';

  @override
  String get restoreFailedTitle => 'Wiederherstellen fehlgeschlagen';

  @override
  String get loadDevicesFailedTitle => 'Geräte konnten nicht geladen werden';

  @override
  String get loadRestorePointsFailedTitle =>
      'Wiederherstellungspunkte konnten nicht gelesen werden';

  @override
  String get loadFailedTitle => 'Die Daten konnten nicht geladen werden';

  @override
  String actionFailedReason(String what, String reason) {
    return '$what – $reason';
  }

  @override
  String get settingsBackupTileBody =>
      'Sicherungsdatei, automatische Kopien, Änderungen in einer Gruppe rückgängig machen';

  @override
  String get backupDecisionTitle => 'Was brauchst du?';

  @override
  String get backupDecisionUndo =>
      'Gerade versehentlich einen Eintrag gelöscht oder geändert? Tippe direkt danach in der Meldung auf „Rückgängig“.';

  @override
  String get backupDecisionGroup =>
      'Einen Fehler in einer Gruppe erst später bemerkt? Mach die Änderungen dieser Gruppe ab einem Zeitpunkt rückgängig – siehe unten „Änderungen in einer Gruppe rückgängig machen“.';

  @override
  String get backupDecisionDevice =>
      'Eine ganze Gruppe ist auf diesem Gerät weg? Nimm einen Wiederherstellungspunkt.';

  @override
  String get backupDecisionDeviceWeb =>
      'Eine ganze Gruppe ist weg? Hol sie aus einer Sicherungsdatei zurück.';

  @override
  String get backupDecisionPhone =>
      'Neues Handy oder dieses verloren? Dann hilft nur eine Sicherungsdatei – bewahre eine aktuelle woanders als auf diesem Gerät auf.';

  @override
  String get backupDecisionPhoneMatrix =>
      'Gruppen, die du mit anderen teilst, kommen nach der erneuten Anmeldung meist von ihnen zurück – Gruppen nur mit dir nicht.';

  @override
  String get backupFileSection => 'Sicherungsdatei';

  @override
  String get backupFileIntro =>
      'Eine Datei mit all deinen Gruppen, die du woanders aufbewahrst – auf einem Computer oder in deiner Cloud. Du kannst sie auf jedem Gerät wiederherstellen.';

  @override
  String get backupFileGroupHint =>
      'Nur eine Gruppe: Gruppe öffnen → Gruppeneinstellungen → Diese Gruppe sichern.';

  @override
  String get backupRestorePointsIntro =>
      'Einmal am Tag legt MoneyLedger automatisch eine Kopie all deiner Gruppen auf diesem Gerät ab. Damit holst du Gruppen oder Einträge zurück, die hier verloren gegangen sind – mit dem Gerät ist sie aber auch weg.';

  @override
  String get backupShowRestorePoints => 'Wiederherstellungspunkte ansehen';

  @override
  String get backupRestorePointsWeb =>
      'Im Browser nicht verfügbar: Er legt keine automatischen Kopien an. Speichere stattdessen regelmäßig eine Sicherungsdatei.';

  @override
  String get backupUndoSection =>
      'Änderungen in einer Gruppe rückgängig machen';

  @override
  String get backupUndoIntro =>
      'Zeigt die Änderungen einer Gruppe auf diesem Gerät und setzt die Gruppe auf den Stand vor einer davon zurück – z. B. nach einem falschen Import. Das ist eine normale Änderung: Wer die Gruppe mit dir teilt, bekommt sie auch.';

  @override
  String get backupUndoPickGroup => 'Gruppe auswählen …';

  @override
  String get backupUndoPickGroupBody =>
      'Auch in den Einstellungen jeder Gruppe: Auf früheren Stand zurücksetzen';

  @override
  String get backupUndoNoGroups => 'Noch keine Gruppen';

  @override
  String get backupUndoPickTitle => 'Welche Gruppe?';

  @override
  String get shareBalances => '„Wer zahlt wem“ teilen';

  @override
  String shareBalanceTitle(String group) {
    return '$group – wer zahlt wem';
  }

  @override
  String get shareAllSettled => 'Alles ausgeglichen.';

  @override
  String shareCurrencyHeader(String currency) {
    return 'In $currency:';
  }

  @override
  String shareDebtLine(String from, String to, String amount) {
    return '$from → $to: $amount';
  }

  @override
  String get shareFooter => 'Erstellt mit MoneyLedger';

  @override
  String get shareCopiedFallback =>
      'Teilen geht hier nicht – der Text wurde in die Zwischenablage kopiert.';

  @override
  String get statsSection => 'Übersicht';

  @override
  String get statsTotalSpent => 'Gesamtausgaben';

  @override
  String statsExpenseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ausgaben',
      one: '1 Ausgabe',
    );
    return '$_temp0';
  }

  @override
  String get statsPerPerson => 'Bezahlt und Anteil pro Person';

  @override
  String statsPaid(String amount) {
    return 'bezahlt $amount';
  }

  @override
  String statsShare(String amount) {
    return 'Anteil $amount';
  }

  @override
  String get statsByCategory => 'Nach Kategorie';

  @override
  String statsMoreCategories(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weitere Kategorien',
      one: '1 weitere Kategorie',
    );
    return '$_temp0';
  }

  @override
  String get verifiedOnlyLearnMore => 'Mehr erfahren';

  @override
  String get verifiedOnlyMoreBody =>
      'Deine eigenen Geräte verifizierst du auf der Geräteseite, die anderer Personen auf der Seite „Personen“ einer Gruppe.\n\nNicht verifizierte Geräte bleiben zurück: Eine neue Anmeldung von dir kann deine Gruppen erst von diesem Gerät wiederherstellen, wenn du sie dort verifizierst.\n\nDie Geräte anderer Personen und deine anderen Geräte synchronisieren weiter untereinander, solange sie das nicht auch einschalten.\n\nWas du empfängst, wird weiter angenommen; die Details eines Eintrags zeigen, ob du das Gerät verifiziert hast, das ihn geschrieben hat. Gilt nur für dieses Gerät und Konto.';

  @override
  String get settingsSectionAdvanced => 'Erweitert (Matrix)';

  @override
  String get webLimitsTitle => 'MoneyLedger im Browser';

  @override
  String get webLimitsBody =>
      'Synchronisiert wird nur, solange dieser Tab offen ist – eine Hintergrund-Synchronisierung gibt es nicht. Automatische Wiederherstellungspunkte gibt es auch nicht, und deine Daten liegen nur in diesem Browser (Websitedaten löschen löscht sie). Sichere sie ab und zu.';

  @override
  String get webLimitsBodyLocal =>
      'Im Browser gibt es keine automatischen Wiederherstellungspunkte, und deine Daten liegen nur in diesem Browser (Websitedaten löschen löscht sie). Sichere sie ab und zu.';

  @override
  String get webLimitsBackup => 'Sichern';

  @override
  String get webLimitsDismiss => 'Verstanden';

  @override
  String get duplicateExpense => 'Duplizieren';

  @override
  String duplicatePersonRenameHint(String name) {
    return 'In dieser Gruppe gibt es schon $name. Ein eindeutiger Name (z. B. „$name B.“) hilft, die beiden auseinanderzuhalten.';
  }

  @override
  String deleteExpenseBodyLocal(String description) {
    return '„$description“ wird von diesem Gerät gelöscht.';
  }

  @override
  String deleteSettlementBodyLocal(String from, String to, String amount) {
    return '„$from hat $to $amount gezahlt“ wird von diesem Gerät gelöscht und der Saldo wiederhergestellt.';
  }

  @override
  String get errorTryAgain => 'Erneut versuchen';

  @override
  String get splitByItemsAction => 'Nach Posten aufteilen …';

  @override
  String get itemsTitle => 'Nach Posten aufteilen';

  @override
  String itemsReceiptTotal(String amount) {
    return 'Gesamt: $amount';
  }

  @override
  String get itemsNoTotal => 'Noch kein Betrag';

  @override
  String get itemsNotStoredHint =>
      'Jeder Posten wird gleichmäßig auf seine Personen aufgeteilt. Gespeichert werden nur die Beträge pro Person, nicht die Posten.';

  @override
  String itemLabel(int n) {
    return 'Posten $n';
  }

  @override
  String get itemAdd => 'Posten hinzufügen';

  @override
  String get itemRemove => 'Posten entfernen';

  @override
  String get itemEveryone => 'Alle';

  @override
  String itemEach(String amount) {
    return 'je $amount';
  }

  @override
  String get itemsEnterOne => 'Gib mindestens einen Postenbetrag ein';

  @override
  String itemsRest(String amount) {
    return 'Rest (Steuer, Trinkgeld, nicht aufgeführt): $amount';
  }

  @override
  String get itemsRestProportional => 'Anteilig';

  @override
  String get itemsRestEqually => 'Gleichmäßig';

  @override
  String get itemsRestProportionalHint =>
      'Der Rest wird im Verhältnis zu dem aufgeteilt, was jede Person hatte.';

  @override
  String get itemsRestEqualHint =>
      'Der Rest wird gleichmäßig auf alle mit einem Posten aufgeteilt.';

  @override
  String get itemsResult => 'Pro Person';

  @override
  String get itemsApply => 'Diese Aufteilung übernehmen';

  @override
  String get receiptPhotoLabel => 'Belegfoto';

  @override
  String get receiptAdd => 'Belegfoto hinzufügen';

  @override
  String get receiptTakePhoto => 'Foto aufnehmen';

  @override
  String get receiptChooseFromGallery => 'Aus der Galerie wählen';

  @override
  String get receiptLocalOnlyHint =>
      'Nur auf diesem Gerät – wird nicht mit der Gruppe geteilt und ist in keiner Sicherung.';

  @override
  String get receiptView => 'Belegfoto ansehen';

  @override
  String get receiptReplace => 'Ersetzen';

  @override
  String get receiptRemove => 'Entfernen';

  @override
  String get receiptUnreadable => 'Dieses Foto kann nicht angezeigt werden.';

  @override
  String get receiptPickFailed => 'Foto konnte nicht übernommen werden';

  @override
  String get receiptSaveFailed =>
      'Die Ausgabe wurde gespeichert, aber ihr Belegfoto konnte nicht abgelegt werden';

  @override
  String get expenseHasReceipt => 'Hat ein Belegfoto';

  @override
  String get privacyReceiptsTitle => 'Belegfotos (Android)';

  @override
  String get privacyReceiptsBody =>
      'Unter Android kannst du einer Ausgabe ein Foto des Belegs anhängen, aufgenommen mit deiner Kamera-App oder aus deinen Fotos ausgewählt. MoneyLedger speichert eine verkleinerte Kopie nur im privaten Speicher der App auf diesem Gerät. Sie wird nie irgendwohin gesendet – nicht an die anderen in der Gruppe, an keinen Homeserver –, ist in keiner Sicherungsdatei, keinem Wiederherstellungspunkt und keiner CSV enthalten und wie alle App-Daten von den Android-Backups ausgenommen. Sie wird mit ihrer Ausgabe gelöscht (beim nächsten Start der App), wenn du die Gruppe verlässt oder löschst und wenn du die lokalen Daten löschst oder die App deinstallierst; beim Abmelden bleibt sie erhalten. Kamera und Fotoauswahl sind die von Android: MoneyLedger fragt nach keiner Kamera- oder Speicherberechtigung und bekommt nur das eine Foto, das du auswählst.';

  @override
  String get receiptSavedSnack => 'Belegfoto gespeichert';

  @override
  String get receiptRemovedSnack => 'Belegfoto entfernt';

  @override
  String get inviteByLink => 'Mit Link einladen';

  @override
  String get inviteByLinkTileBody => 'Link oder QR-Code teilen – ohne Konto';

  @override
  String get inviteByLinkTileBodyOpen => 'Einladungslink und QR-Code anzeigen';

  @override
  String get linkInviteSheetBody =>
      'Schick diesen Link an die Personen in der Gruppe. Sie öffnen ihn in MoneyLedger und wählen aus, wer sie sind – ohne Konto.';

  @override
  String get linkInviteQrLabel => 'QR-Code des Einladungslinks';

  @override
  String get linkInviteQrHint =>
      'Oder lass sie diesen Code mit der Kamera ihres Handys scannen.';

  @override
  String get linkInviteShare => 'Link teilen';

  @override
  String get linkInviteCopied => 'Einladungslink kopiert';

  @override
  String get linkInviteWarning =>
      'Alle, die diesen Link haben, können die Gruppe sehen und ändern. Teile ihn nur mit den Personen darin.';

  @override
  String get linkInviteRecoveryHint =>
      'Wird etwas versehentlich geändert oder gelöscht, kannst du die Gruppe in den Gruppeneinstellungen auf einen früheren Stand zurücksetzen.';

  @override
  String get linkInviteMatrixGroup =>
      'Diese Gruppe wird mit Matrix-Konten geteilt und kann deshalb noch keinen Einladungslink bekommen. Lade Personen auf der Personen-Seite per Matrix-ID ein.';

  @override
  String get linkDisclosureTitle => 'Teilen mit einem Link';

  @override
  String linkDisclosureRelays(String relays) {
    return 'Geteilte Gruppen synchronisieren über öffentliche Nostr-Relays: $relays. Das sind unabhängige Dienste mit eigenen Nutzungsbedingungen (verlinkt unter Einstellungen → Relays).';
  }

  @override
  String get linkDisclosureEncrypted =>
      'Sie speichern deine Gruppe verschlüsselt – lesen können sie nur Personen mit dem Link.';

  @override
  String get linkDisclosureMetadata =>
      'Die Relays sehen deine IP-Adresse und wann du synchronisierst und behalten Daten eventuell länger als die 30 Tage, um die wir bitten.';

  @override
  String get linkDisclosureAnyone =>
      'Alle mit dem Link können die Gruppe sehen und ändern.';

  @override
  String get linkDisclosureMatrix =>
      'Du willst Konten und verifizierte Geräte? Nutze Matrix (sicherer Modus).';

  @override
  String get linkDisclosureContinue => 'Weiter';

  @override
  String get createGroupShareByLink => 'Mit Einladungslink teilen';

  @override
  String get createGroupShareByLinkBody =>
      'Andere machen ohne Konto mit. Alle mit dem Link können die Gruppe sehen und ändern. Aus: Du lädst Matrix-Konten ein (sicher).';

  @override
  String get linkMembersHint =>
      'Mit Link geteilt: Personen werden mit Namen hinzugefügt. Wer den Einladungslink öffnet, wählt die passende Person aus.';

  @override
  String get privacyLinkTitle => 'Geteilte Gruppen (Einladungslink)';

  @override
  String get privacyLinkBody =>
      'Eine Gruppe, die du mit einem Einladungslink teilst, synchronisiert über öffentliche Nostr-Relays – standardmäßig nos.lol und nostr.mom, die denselben Betreiber haben. Das sind unabhängige Dienste mit eigenen Nutzungsbedingungen. Unter Einstellungen → Relays kannst du die Relays ändern: Ein neues wird zuerst nach seiner Infoseite (NIP-11) gefragt, danach synchronisieren deine geteilten Gruppen auch darüber. Jedes Gerät in der Gruppe veröffentlicht dort seine Kopie der Gruppe, verschlüsselt (AES-256-GCM) mit einem Schlüssel, den nur der Link enthält; der Schlüssel geht nie an ein Relay oder an einen Server von uns. Die Relays können keine Namen, Beträge oder Notizen lesen, sehen aber die IP-Adresse deines Geräts, wann es synchronisiert, ungefähr wie groß die Gruppe ist und wie viele Geräte mitmachen und dass die Daten von MoneyLedger kommen. Wir bitten sie, jede Kopie nach 30 Tagen zu löschen (erneuert, solange die Gruppe genutzt wird), aber Relays können Daten länger behalten oder archivieren – und wer den Link bekommt, jetzt oder später, kann die Gruppe lesen und ändern, auch aus archivierten Kopien. Wenn du eine geteilte Gruppe von diesem Gerät löschst (oder die lokalen Daten löschst), bittet die App die Relays zuerst, deine Kopie zu löschen; die anderen in der Gruppe behalten ihre. Wenn du den Einladungslink zurücksetzt (oder auf einen neuen Link umstellst, den dir jemand geschickt hat), bittet die App die Relays, deine Kopie unter dem alten Link zu löschen, und veröffentlicht die Gruppe mit einem neuen Schlüssel; wer nur den alten Link hat, bekommt deine Änderungen nicht mehr, behält aber, was schon gesehen wurde. Eine Gruppe, die nur auf diesem Gerät liegt, kontaktiert nie ein Relay: Eine Gruppe synchronisiert erst, wenn du mit einem Link einlädst, sie mit „Mit Einladungslink teilen“ erstellst oder ihr mit einem Link beitrittst, den du bekommen hast – oder, in einer Gruppe, die mit Matrix-Konten geteilt wird, wenn jemand darin mit einem Link einlädt: Dann teilen deine Geräte diese Gruppe ebenso über die Relays, und Änderungen über den Link werden als „nicht überprüft“ markiert. In einer solchen Gruppe – auch sobald jemand, der per Link beigetreten ist, ein Matrix-Konto verbindet – sieht jede Person mit dem Link die Matrix-IDs derer, die Matrix nutzen. Wird eine solche Gruppe abgesichert (sobald alle darin ein Matrix-Konto haben), werden die Relays gebeten, die Kopien zu löschen, und der Link funktioniert nicht mehr. Ein geöffneter Einladungslink kontaktiert nichts, bis du auf „Beitreten“ tippst; dann werden die Relays nach dieser Gruppe gefragt.';

  @override
  String linkInviteShareText(String group, String link) {
    return 'Mach mit bei „$group“ in MoneyLedger: $link';
  }

  @override
  String get joinLinkTitle => 'Gruppe beitreten';

  @override
  String get joinLinkEntry => 'Mit Einladungslink beitreten';

  @override
  String get joinLinkPasteHint =>
      'Füge den Einladungslink ein, den du bekommen hast.';

  @override
  String get joinLinkPasteLabel => 'Einladungslink';

  @override
  String get joinLinkContinue => 'Weiter';

  @override
  String get joinLinkInvalidTitle => 'Dieser Einladungslink funktioniert nicht';

  @override
  String get joinLinkInvalidBody =>
      'Prüf, ob der ganze Link kopiert wurde, oder lass ihn dir noch mal schicken.';

  @override
  String get joinLinkUpdateApp =>
      'Für diesen Einladungslink brauchst du eine neuere Version von MoneyLedger. Bitte aktualisiere die App.';

  @override
  String get joinLinkInvited => 'Du wurdest zu einer Gruppe eingeladen.';

  @override
  String get joinLinkIntroBody =>
      'MoneyLedger sucht die Gruppe über die Relays und fragt dann, wer du in der Gruppe bist.';

  @override
  String get joinLinkNoAccountHint =>
      'Kein Konto nötig: MoneyLedger startet auf diesem Gerät ohne Konto.';

  @override
  String get joinLinkSearching => 'Gruppe wird gesucht …';

  @override
  String get joinLinkNotFoundTitle => 'Gruppe noch nicht gefunden';

  @override
  String get joinLinkNotFoundBody =>
      'Die Person, die dich eingeladen hat, muss MoneyLedger einmal öffnen, damit die Gruppe geteilt wird. Versuch es gleich noch mal.';

  @override
  String get joinLinkRetry => 'Noch mal versuchen';

  @override
  String get joinLinkBlockedTitle => 'Beitreten mit diesem Link nicht möglich';

  @override
  String get joinLinkNotALinkGroup =>
      'Diese Gruppe ist schon auf diesem Gerät und wird hier nicht per Link geteilt – dieser Link kann sie nicht hinzufügen.';

  @override
  String get joinLinkOtherLink =>
      'Diese Gruppe ist schon mit einem anderen Einladungslink auf diesem Gerät.';

  @override
  String get joinLinkUsedElsewhere => 'Schon auf einem anderen Handy gewählt';

  @override
  String get joinLinkPersonGone =>
      'Diese Person ist nicht mehr in der Gruppe. Bitte wähl neu.';

  @override
  String joinLinkInvitedTo(String group) {
    return 'Du wurdest zu „$group“ eingeladen.';
  }

  @override
  String joinLinkPickTitle(String group) {
    return 'Wer bist du in „$group“?';
  }

  @override
  String get syncSheetTitle => 'Synchronisierung';

  @override
  String get syncSheetAllSynced => 'Alle haben deine neuesten Änderungen.';

  @override
  String get syncSheetPending =>
      'Noch haben nicht alle deine neuesten Änderungen.';

  @override
  String get syncSheetNoPeers =>
      'Sonst hat niemand in dieser Gruppe ein Matrix-Konto – es gibt nichts zu synchronisieren.';

  @override
  String get syncSheetLocalPeople =>
      'Personen ohne Matrix-Konto synchronisieren nicht – sie sind nur Einträge in der Abrechnung.';

  @override
  String get peerUpToDate => 'Hat alles';

  @override
  String peerUpToDateAt(String ago) {
    return 'Hat alles · geprüft $ago';
  }

  @override
  String peerWaitingSince(String ago) {
    return 'Wartet – zuletzt synchron $ago';
  }

  @override
  String get peerWaitingNever => 'Wartet – noch nicht synchron';

  @override
  String get peerNoDevice =>
      'Kein angemeldetes Gerät – synchronisiert, sobald die Person sich anmeldet';

  @override
  String get peerUnverified =>
      'Kein verifiziertes Gerät – verifiziere eines, um zu synchronisieren';

  @override
  String get peerYourDevices => 'Deine anderen Geräte';

  @override
  String get peerUnknown => 'Unbekannte Person';

  @override
  String peerPublishedAt(String ago) {
    return 'Letzte Aktualisierung $ago';
  }

  @override
  String get peerDeletedGroup => 'Hat die Gruppe gelöscht';

  @override
  String peerDeletedGroupAt(String ago) {
    return 'Hat die Gruppe gelöscht – $ago';
  }

  @override
  String peerDevices(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Geräte',
      one: '1 Gerät',
    );
    return '$_temp0';
  }

  @override
  String get syncSheetLinkNoPeers =>
      'Noch hat niemand sonst den Einladungslink geöffnet.';

  @override
  String get syncSheetLinkHint =>
      'Wer den Einladungslink noch nicht geöffnet hat, erscheint hier nicht. „Hat alles“ heißt: Das Gerät hat denselben Stand veröffentlicht wie deines.';

  @override
  String linkSyncSynced(String ago) {
    return 'Deine Änderungen liegen auf den Relays ($ago).';
  }

  @override
  String get linkSyncSyncedNoTime => 'Deine Änderungen liegen auf den Relays.';

  @override
  String get linkSyncPending =>
      'Deine Änderungen werden an die Relays gesendet …';

  @override
  String get linkSyncNotDelivered =>
      'Die Relays sind nicht erreichbar – es wird erneut versucht.';

  @override
  String get linkSyncRelaysReject =>
      'Die Relays lehnen unsere Aktualisierungen ab. Füge unter Einstellungen → Relays ein anderes hinzu.';

  @override
  String get linkSyncTooLarge =>
      'Diese Gruppe ist zu groß zum Teilen per Link.';

  @override
  String get linkSyncNoParticipant =>
      'Wähle zuerst, wer du in dieser Gruppe bist.';

  @override
  String get linkSyncMergeFailed =>
      'Eine Aktualisierung konnte nicht gespeichert werden – es wird erneut versucht.';

  @override
  String get linkCloudSynced => 'Über die Relays synchronisiert';

  @override
  String get linkCloudOffline => 'Offline – kein Relay erreichbar';

  @override
  String get linkSyncOffline =>
      'Gerade ist kein Relay erreichbar – bist du offline? Was sich seit der letzten Synchronisierung geändert hat, wird gesendet, sobald die Verbindung wieder da ist.';

  @override
  String get syncNow => 'Jetzt synchronisieren';

  @override
  String get syncNowSent =>
      'Alle wurden nach ihrem Stand gefragt – sie antworten, sobald ihre App läuft.';

  @override
  String get syncNowChecked => 'Relays abgefragt.';

  @override
  String get syncNowUnreachable => 'Die Relays sind nicht erreichbar.';

  @override
  String get relaysTitle => 'Relays';

  @override
  String relaysTileBody(String relays) {
    return 'Gruppen mit Einladungslink synchronisieren über: $relays';
  }

  @override
  String get relaysTileProblem => 'Ein Relay lehnt unsere Aktualisierungen ab';

  @override
  String get relaysIntro =>
      'Mit Einladungslink geteilte Gruppen synchronisieren über diese öffentlichen Nostr-Relays. Sie speichern jede Gruppe verschlüsselt und sehen deine IP-Adresse und wann du synchronisierst. Es sind unabhängige Dienste mit eigenen Nutzungsbedingungen.';

  @override
  String get relaysOneOperator =>
      'nos.lol und nostr.mom haben denselben Betreiber. Nehmen sie keine Aktualisierungen mehr an, synchronisieren Gruppen nur noch über ein Relay, das du hinzufügst – zum Beispiel dein eigenes.';

  @override
  String get relaysCommon =>
      'Der Einladungslink nennt keine Relays: Alle in einer Gruppe brauchen mindestens ein gemeinsames Relay. Diese Liste gilt nur für dieses Gerät.';

  @override
  String relayStatusRejects(String message) {
    return 'Lehnt unsere Aktualisierungen ab: $message';
  }

  @override
  String relayStatusRateLimited(int n) {
    return 'Bittet um eine Pause – nächster Versuch in $n Min.';
  }

  @override
  String get relayStatusNeedsAccount => 'Braucht ein Konto – nicht nutzbar';

  @override
  String get relayStatusNoExpiration => 'Unterstützt kein Ablaufdatum (NIP-40)';

  @override
  String relayStatusLastRefused(String ago, String message) {
    return 'Hat unsere letzte Aktualisierung abgelehnt ($ago): $message';
  }

  @override
  String relayStatusOk(String ago) {
    return 'Hat unsere letzte Aktualisierung $ago angenommen';
  }

  @override
  String get relayStatusUnused => 'Noch nicht genutzt';

  @override
  String get relayTerms => 'Bedingungen';

  @override
  String relayTermsOf(String relay) {
    return 'Bedingungen von $relay';
  }

  @override
  String relayRemove(String relay) {
    return '$relay entfernen';
  }

  @override
  String relayRemoveConfirmTitle(String relay) {
    return '$relay entfernen?';
  }

  @override
  String get relayRemoveConfirmBody =>
      'Dieses Gerät synchronisiert geteilte Gruppen dann nicht mehr darüber.';

  @override
  String get relayRemoveConfirm => 'Entfernen';

  @override
  String get relayRemoved => 'Relay entfernt.';

  @override
  String get relayAdd => 'Relay hinzufügen …';

  @override
  String get relayAddTitle => 'Relay hinzufügen';

  @override
  String get relayAddLabel => 'Relay-Adresse';

  @override
  String get relayAddConfirm => 'Hinzufügen';

  @override
  String get relayAddInvalid =>
      'Das ist keine Relay-Adresse (z. B. wss://relay.example.org).';

  @override
  String get relayAddNotSecure =>
      'Nur verschlüsselte Verbindungen (wss://) werden unterstützt.';

  @override
  String get relayAddDuplicate => 'Dieses Relay ist schon in der Liste.';

  @override
  String get relayAddChecking => 'Relay wird geprüft …';

  @override
  String get relayAddNeedsAccount =>
      'Dieses Relay braucht ein Konto – es kann nicht genutzt werden.';

  @override
  String get relayAddNoExpiration =>
      'Dieses Relay unterstützt kein Ablaufdatum (NIP-40) – es würde deine Gruppen unbegrenzt aufbewahren.';

  @override
  String get relayAddUncheckedTitle => 'Relay konnte nicht geprüft werden';

  @override
  String get relayAddUncheckedBody =>
      'Es hat auf die Prüfung (NIP-11) nicht geantwortet – vielleicht ist es offline oder die Adresse stimmt nicht. Trotzdem hinzufügen?';

  @override
  String get relayAddAnyway => 'Trotzdem hinzufügen';

  @override
  String get relayAdded =>
      'Relay hinzugefügt – deine geteilten Gruppen werden jetzt dorthin gesendet.';

  @override
  String get relaysRestoreDefaults => 'Standard-Relays verwenden';

  @override
  String get relaysDefaultsRestored => 'Standard-Relays wiederhergestellt.';

  @override
  String get backgroundSyncLocalBody =>
      'Auch etwa alle 15 Minuten die Relays nach deinen geteilten Gruppen fragen, wenn die App geschlossen ist.';

  @override
  String linkDisclosureRelaysOneOperator(String relays) {
    return 'Geteilte Gruppen synchronisieren über zwei öffentliche Nostr-Relays, $relays (ein Betreiber). Das sind unabhängige Dienste mit eigenen Nutzungsbedingungen (verlinkt unter Einstellungen → Relays).';
  }

  @override
  String get linkDisclosureOwnRelay =>
      'Unter Einstellungen → Relays kannst du ein eigenes Relay hinzufügen.';

  @override
  String get deleteLinkGroupNote =>
      'Diese Gruppe ist per Einladungslink geteilt: Die anderen behalten ihre Kopien. Deine Kopie wird von den Relays entfernt, und mit dem Link kannst du wieder beitreten.';

  @override
  String get linkUnpublishing => 'Deine Kopie wird von den Relays entfernt …';

  @override
  String deleteLocalDataLinkNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count davon sind per Einladungslink geteilt: Die anderen behalten ihre Kopien, deine werden von den Relays entfernt.',
      one:
          'Eine davon ist per Einladungslink geteilt: Die anderen behalten ihre Kopien, deine wird von den Relays entfernt.',
    );
    return '$_temp0';
  }

  @override
  String backupLinkKeysWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Die Datei enthält die Einladungsschlüssel von $count geteilten Gruppen: Wer die Datei hat, kann sie lesen und ändern.',
      one:
          'Die Datei enthält den Einladungsschlüssel einer geteilten Gruppe: Wer die Datei hat, kann diese Gruppe lesen und ändern.',
    );
    return '$_temp0';
  }

  @override
  String restoreLinkKeysWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Diese Datei enthält die Einladungsschlüssel von $count geteilten Gruppen: Wer die Datei hat, kann sie lesen und ändern. Öffne sie nach der Wiederherstellung und wähle jeweils, wer du bist – dann synchronisieren sie wieder.',
      one:
          'Diese Datei enthält den Einladungsschlüssel einer geteilten Gruppe: Wer die Datei hat, kann sie lesen und ändern. Öffne die Gruppe nach der Wiederherstellung und wähle, wer du bist – dann synchronisiert sie wieder.',
    );
    return '$_temp0';
  }

  @override
  String get backupFileLinkNote =>
      'Die Datei enthält auch die Einladungsschlüssel deiner geteilten Gruppen – damit kann jeder sie lesen und ändern. Lege beim Speichern eine Passphrase fest.';

  @override
  String get linkChooseMeBanner =>
      'Welche Person bist du in dieser Gruppe? Sobald du wählst, synchronisiert sie wieder.';

  @override
  String get linkResetMenu => 'Einladungslink zurücksetzen';

  @override
  String get linkResetTileBody =>
      'Neuer Link – der alte funktioniert dann nicht mehr';

  @override
  String get linkResetSheetHint =>
      'Zum Beispiel, nachdem du jemanden entfernt hast: Wer diesen Link hat, kann die Gruppe weiterhin öffnen.';

  @override
  String get linkResetTitle => 'Einladungslink zurücksetzen?';

  @override
  String get linkResetBody =>
      'Damit erstellst du einen neuen Einladungslink. Deine Änderungen gehen dann nur noch an Personen, die den neuen Link nutzen – schick ihn also allen, die noch in der Gruppe sind.\n\nWer nur den alten Link hat (zum Beispiel eine Person, die du entfernt hast), sieht deine Änderungen nicht mehr; was schon gesehen wurde, bleibt dort. Ganz funktioniert der alte Link erst nicht mehr, wenn alle zum neuen gewechselt sind.';

  @override
  String get linkResetConfirm => 'Link zurücksetzen';

  @override
  String get linkResetting => 'Einladungslink wird zurückgesetzt …';

  @override
  String get linkResetFailed =>
      'Einladungslink konnte nicht zurückgesetzt werden';

  @override
  String get linkResetDoneHint =>
      'Das ist der neue Link. Schick ihn allen, die noch in der Gruppe sind – bis sie ihn öffnen, seht ihr die Änderungen der anderen nicht.';

  @override
  String removeMemberLinkNote(Object name) {
    return '$name kann die Gruppe mit dem Einladungslink weiterhin öffnen. Um das zu verhindern, setz danach den Einladungslink zurück (Gruppeneinstellungen) und schick den neuen an die anderen.';
  }

  @override
  String joinLinkSwitchTitle(Object group) {
    return '„$group“ auf diesen Link umstellen?';
  }

  @override
  String get joinLinkSwitchTitleNoName => 'Auf diesen Link umstellen?';

  @override
  String get joinLinkSwitchBody =>
      'Diese Gruppe ist schon mit einem anderen Einladungslink auf diesem Gerät. Wenn jemand aus der Gruppe den Link zurückgesetzt und dir diesen geschickt hat, stell auf ihn um: Du bleibst dieselbe Person, und dein Handy synchronisiert dann mit allen, die den neuen Link nutzen.';

  @override
  String get joinLinkSwitchCaution =>
      'Stell nur um, wenn du den Link von jemandem aus der Gruppe hast. Deine Kopie wird vom alten Link entfernt.';

  @override
  String get joinLinkSwitchConfirm => 'Diesen Link nutzen';

  @override
  String get joinLinkSwitchKeep => 'Alten Link behalten';

  @override
  String get recordViaLink => 'Über den Einladungslink · nicht überprüft';

  @override
  String recordViaLinkBy(String name) {
    return 'Von $name über den Einladungslink geändert · nicht überprüft';
  }

  @override
  String get errorSignatureRequiredTitle =>
      'Nur mit einem Matrix-Konto möglich';

  @override
  String get errorSignatureRequiredHint =>
      'In dieser Gruppe können Name, Währung, Kategorien und Personen mit Matrix-Konto nur von jemandem geändert werden, der mit Matrix angemeldet ist.';

  @override
  String get linkMixedTitle => 'Diese Gruppe auch per Link teilen?';

  @override
  String get linkMixedBody =>
      'Wer den Link hat, kann diese Gruppe dann ohne Konto sehen und ändern – und sieht die Matrix-IDs der Personen darin. Diese Änderungen werden als „nicht überprüft“ markiert, und Name, Währung und Kategorien können nur Personen ändern, die mit Matrix angemeldet sind.\n\nDeine Geräte und die der anderen, die mit Matrix angemeldet sind, teilen die Gruppe dann auch über die Relays, verschlüsselt mit dem Schlüssel des Links.\n\nSobald alle ein Matrix-Konto haben, kannst du die Gruppe wieder absichern: Der Link funktioniert dann nicht mehr.';

  @override
  String get linkMixedConfirm => 'Per Link teilen';

  @override
  String get linkMixedOpening => 'Einladungslink wird erstellt …';

  @override
  String get lockGroupTile => 'Gruppe absichern';

  @override
  String get lockGroupTileBody =>
      'Ab jetzt nur noch Matrix-Konten – der Einladungslink funktioniert dann nicht mehr';

  @override
  String get lockBlockedTitle => 'Noch nicht alle haben ein Matrix-Konto';

  @override
  String lockBlockedBody(String names) {
    return 'Bevor die Gruppe abgesichert werden kann, müssen diese Personen in MoneyLedger ein Matrix-Konto verbinden (Einstellungen → Matrix-Konto verbinden) – oder aus der Gruppe entfernt werden: $names';
  }

  @override
  String get lockConfirmTitle => 'Diese Gruppe absichern?';

  @override
  String get lockConfirmBody =>
      'Der Einladungslink funktioniert dann nicht mehr: Die Relays werden gebeten, die Kopien der Gruppe zu löschen, und Änderungen über den Link werden nicht mehr angenommen. Alle synchronisieren weiter mit ihrem Matrix-Konto.\n\nDu kannst die Gruppe später wieder per Link teilen – mit einem neuen Link.';

  @override
  String get lockConfirm => 'Absichern';

  @override
  String get lockRunning => 'Gruppe wird abgesichert …';

  @override
  String get lockDone =>
      'Die Gruppe ist jetzt abgesichert – nur noch Matrix-Konten.';

  @override
  String get lockFailed => 'Die Gruppe konnte nicht abgesichert werden';

  @override
  String get secureOnlyBanner =>
      'Diese Gruppe ist jetzt nur noch mit Matrix nutzbar – melde dich mit Matrix an, um sie weiter zu nutzen.';

  @override
  String get onboardingInviteLinkTitle => 'Mit Link einladen';

  @override
  String get onboardingInviteLinkBody =>
      'Tippe in einer Gruppe auf ⋮ → Mit Link einladen: Die anderen öffnen den Link und wählen ihren Namen – ohne Konto. Wer den Link hat, kann die Gruppe sehen und ändern.';

  @override
  String get welcomeLinkTitle => 'Gruppen per Link teilen';

  @override
  String get welcomeLinkBody =>
      'Schick den anderen einen Einladungslink – per Messenger, E-Mail oder als QR-Code. Sie öffnen ihn, wählen ihren Namen, und alle sehen dieselben Ausgaben. Niemand braucht ein Konto.';

  @override
  String get welcomeLinkEncrypted =>
      'Die Gruppe wird verschlüsselt über öffentliche Nostr-Relays synchronisiert – nur wer den Link hat, kann sie lesen.';

  @override
  String get welcomeLinkRelays =>
      'Die Relays sehen deine IP-Adresse und wann du synchronisierst, nie den Inhalt.';

  @override
  String get welcomeLinkAnyone =>
      'Wer den Link hat, kann die Gruppe sehen und ändern – teile ihn nur mit den Personen darin.';

  @override
  String get welcomeSecureTitle => 'Mehr Sicherheit? Matrix';

  @override
  String get welcomeSecureBody =>
      'Matrix ist ein offenes, dezentrales Nachrichtennetz. Wie bei E-Mail wählst du einen Anbieter (einen „Homeserver“, z. B. matrix.org) und legst dort ein kostenloses Konto an. Angemeldet synchronisiert MoneyLedger deine Gruppen Ende-zu-Ende-verschlüsselt mit den Personen, die du hinzugefügt hast – der sichere Modus.';

  @override
  String get welcomeSecureMembers =>
      'Nur die Personen, die du hinzugefügt hast, bekommen eine Gruppe – jede Änderung ist vom Gerät signiert, das sie gemacht hat.';

  @override
  String get welcomeSecureHeading => 'Sicherer Modus';

  @override
  String get welcomeSecureHint =>
      'Mit einem kostenlosen Matrix-Konto: nur Personen, die du hinzugefügt hast, signierte Änderungen, deine Gruppen auf jedem Gerät.';

  @override
  String get whyMatrixTitle => 'Warum Matrix?';

  @override
  String get whyMatrixEasyTitle => 'Links sind einfach';

  @override
  String get whyMatrixEasyBody =>
      'Ein Link ist der schnellste Weg, eine Gruppe zu teilen: verschicken, die anderen wählen ihren Namen, fertig. Kein Konto, keine Anmeldung – deshalb ist er der Standard, und für eine Reise oder ein Essen reicht er oft völlig.';

  @override
  String get whyMatrixCompareTitle => 'Es gibt noch einen Modus';

  @override
  String get whyMatrixCompareBody =>
      'Matrix ist auch kostenlos und funktioniert noch besser – du meldest dich nur an. Was sich ändert:';

  @override
  String get whyMatrixWhoTitle => 'Wer eine Gruppe sehen und ändern kann';

  @override
  String get whyMatrixWhoLink =>
      'alle, die den Link haben – auch wenn er weitergeleitet wird.';

  @override
  String get whyMatrixWhoMatrix =>
      'nur die Personen, die du hinzugefügt hast; jede Änderung ist vom Gerät signiert, das sie gemacht hat.';

  @override
  String get whyMatrixRemoveTitle => 'Jemanden entfernen';

  @override
  String get whyMatrixRemoveLink =>
      'die Person behält Zugriff, bis du den Link zurücksetzt und den neuen an alle anderen schickst.';

  @override
  String get whyMatrixRemoveMatrix =>
      'das gilt sofort – ihre Änderungen werden ab dann ignoriert.';

  @override
  String get whyMatrixPhoneTitle => 'Neues oder verlorenes Handy';

  @override
  String get whyMatrixPhoneLink =>
      'du brauchst den Link (oder eine Sicherung) wieder.';

  @override
  String get whyMatrixPhoneMatrix =>
      'anmelden – deine Gruppen kommen von deinen anderen Geräten oder den anderen in der Gruppe zurück.';

  @override
  String get whyMatrixServersTitle => 'Wer was sieht';

  @override
  String get whyMatrixServersLink =>
      'öffentliche Relays von Freiwilligen sehen deine IP-Adresse, wann du synchronisierst und ungefähr, wie groß die Gruppe ist.';

  @override
  String get whyMatrixServersMatrix =>
      'nur die Homeserver der Personen in der Gruppe (jede Person wählt ihren eigenen) sehen, wer mit wem Nachrichten austauscht – nie den Inhalt.';

  @override
  String get whyMatrixReadyTitle => 'Wenn du so weit bist';

  @override
  String get whyMatrixReadyConnectBody =>
      'Leg ein kostenloses Konto an, z. B. bei matrix.org, und verbinde es. Deine Gruppen kommen mit; per Link geteilte Gruppen behalten ihren Link und werden zusätzlich über Matrix synchronisiert.';

  @override
  String get whyMatrixReadySignInBody =>
      'Leg ein kostenloses Konto an, z. B. bei matrix.org, und melde dich an – oder starte ohne Konto und verbinde später eins.';

  @override
  String get whyMatrixReadySignedInBody =>
      'Du bist schon mit Matrix angemeldet. Gruppen, die du anlegst, sind Matrix-Gruppen. In einer Gruppe, die auch per Link geteilt ist, schließt „Gruppe absichern“ (Gruppeneinstellungen) den Link, sobald alle darin mit Matrix dabei sind.';

  @override
  String get whyMatrixReadyLaterBody =>
      'Matrix ist kostenlos. Du kannst jederzeit später in den Einstellungen ein Konto verbinden – deine Gruppen kommen mit.';

  @override
  String get whyMatrixNotNow => 'Jetzt nicht';

  @override
  String get whyMatrixHintTitle => 'Es gibt auch einen sicheren Modus';

  @override
  String get whyMatrixHintBody =>
      'Deine Link-Gruppe ist richtig in Gebrauch. Mit einem kostenlosen Matrix-Konto sehen eine Gruppe nur die Personen, die du hinzugefügt hast, und jede Änderung ist signiert.';

  @override
  String get whyMatrixHintBodyMatrix =>
      'Deine Link-Gruppe ist richtig in Gebrauch. Wer ihren Link hat, kann sie sehen und ändern. Gruppen, die du mit deinem Matrix-Konto erstellst, sehen nur die Personen, die du hinzugefügt hast, und jede Änderung ist signiert.';

  @override
  String get whyMatrixHintMore => 'Mehr erfahren';

  @override
  String whyMatrixWithLink(String text) {
    return 'Link: $text';
  }

  @override
  String whyMatrixWithMatrix(String text) {
    return 'Matrix: $text';
  }

  @override
  String get exchangeRatesTitle => 'Wechselkurse';

  @override
  String get exchangeRatesTileNone =>
      'Nicht festgelegt – Währungen werden getrennt ausgeglichen';

  @override
  String exchangeRatesTileRates(int count, String base) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kurse in $base',
      one: '1 Kurs in $base',
    );
    return '$_temp0';
  }

  @override
  String exchangeRatesTileSettled(String rates, String base) {
    return '$rates · Ausgleich in $base';
  }

  @override
  String exchangeRatesIntro(String base) {
    return 'Feste Kurse, die du selbst einträgst. Sie gehören zur Gruppe: Alle in der Gruppe sehen und nutzen dieselben Kurse. Die Kurse gelten in $base.';
  }

  @override
  String settleInBase(String base) {
    return 'In $base ausgleichen';
  }

  @override
  String get settleInBaseBody =>
      'Salden und Zahlungsvorschläge rechnen die anderen Währungen zu diesen Kursen um. Eine Währung ohne Kurs bleibt getrennt.';

  @override
  String rateRow(String from, String rate, String base) {
    return '1 $from = $rate $base';
  }

  @override
  String get addRate => 'Kurs hinzufügen';

  @override
  String get removeRate => 'Kurs entfernen';

  @override
  String get noRatesYet => 'Noch keine Kurse.';

  @override
  String ratesMissingFor(String currencies) {
    return 'In der Gruppe ohne Kurs: $currencies';
  }

  @override
  String rateDialogTitle(String from, String base) {
    return '1 $from in $base';
  }

  @override
  String rateFieldLabel(String base) {
    return 'Kurs in $base';
  }

  @override
  String get rateInvalid =>
      'Gib eine Zahl größer als 0 ein (höchstens 10 Nachkommastellen).';

  @override
  String get fetchRate => 'Aktuellen Kurs abrufen';

  @override
  String fetchRateSource(String host) {
    return 'Fragt Frankfurter ($host, Referenzkurse der Zentralbanken) – nur wenn du tippst. Der Dienst sieht deine IP-Adresse und die zwei Währungen, nichts über die Gruppe.';
  }

  @override
  String fetchedRateFrom(String date) {
    return 'Referenzkurs vom $date (Frankfurter) – prüf ihn vor dem Speichern.';
  }

  @override
  String get fetchRateUnavailable =>
      'Für diese Währungen gibt es keinen Kurs – trag ihn selbst ein.';

  @override
  String get fetchRateFailedTitle => 'Kurs konnte nicht abgerufen werden';

  @override
  String settledInBaseNote(String base) {
    return 'Ausgleich in $base: Andere Währungen werden zu den festen Kursen der Gruppe umgerechnet.';
  }

  @override
  String get setExchangeRates => 'Wechselkurse festlegen';

  @override
  String get privacyRatesTitle => 'Wechselkurse';

  @override
  String get privacyRatesBody =>
      'Eine Gruppe kann feste Wechselkurse haben, die du selbst einträgst; sie gehören zur Gruppe und werden wie ihr Name mit allen in der Gruppe synchronisiert. Nur wenn du auf „Aktuellen Kurs abrufen“ tippst, fragt die App Frankfurter (api.frankfurter.dev – ein kostenloser Open-Source-Dienst mit den Referenzkursen der Europäischen Zentralbank und anderer Zentralbanken) nach dem Kurs zwischen den zwei Währungen. Die Anfrage geht direkt von deinem Gerät aus und braucht kein Konto und keinen Schlüssel; der Dienst (und sein Hosting-Anbieter) sieht die IP-Adresse deines Geräts, die zwei Währungscodes und die Uhrzeit – nichts über deine Gruppen, die Personen darin oder Beträge. Er wird nie automatisch kontaktiert, und der abgerufene Kurs wird nur eingetragen, damit du ihn vor dem Speichern prüfst.';

  @override
  String get settingsSectionPayment => 'Zahlungsdaten';

  @override
  String get paymentDetailsTileTitle => 'Bankkonto & PayPal.me';

  @override
  String get paymentDetailsTileNone =>
      'Optional – deine Gruppen sehen sie, wenn sie dir Geld zurückzahlen';

  @override
  String paymentDetailsTileIban(String last4) {
    return 'IBAN endet auf $last4';
  }

  @override
  String get paymentDetailsIntro =>
      'Optional. Alle in deinen Gruppen bekommen sie, damit sie dir Geld zurückzahlen können: Die Saldo-Seite zeigt einen GiroCode für die Banking-App (nur Euro) oder deinen PayPal.me-Link mit dem Betrag – auf deinem Handy zum Scannen und auf ihrem, wenn sie dir etwas schulden.';

  @override
  String get paymentBankSection => 'Bankkonto (SEPA)';

  @override
  String get paymentNameLabel => 'Name auf dem Konto';

  @override
  String get paymentNameRequired =>
      'Gib den Namen auf dem Konto ein – die Bank braucht ihn.';

  @override
  String get paymentIbanLabel => 'IBAN';

  @override
  String get paymentIbanInvalid =>
      'Das ist keine gültige IBAN – prüf sie auf Tippfehler.';

  @override
  String get paymentBicLabel => 'BIC (optional)';

  @override
  String get paymentBicHelper =>
      'Nur für manche Banken außerhalb der EU nötig.';

  @override
  String get paymentBicInvalid =>
      'Eine BIC hat 8 oder 11 Buchstaben und Ziffern.';

  @override
  String get paymentPaypalSection => 'PayPal';

  @override
  String get paymentPaypalLabel => 'PayPal.me-Name';

  @override
  String get paymentPaypalHelper =>
      'Dein Name aus dem Link paypal.me/name – du kannst auch den ganzen Link einfügen.';

  @override
  String get paymentPaypalInvalid =>
      'Nur Buchstaben und Ziffern, höchstens 20.';

  @override
  String get paymentDetailsClear => 'Alle Felder leeren';

  @override
  String get paymentDetailsSaved => 'Zahlungsdaten gespeichert';

  @override
  String get paymentDetailsCleared => 'Zahlungsdaten entfernt';

  @override
  String get paymentShowDetails => 'Meine Zahlungsdaten zeigen';

  @override
  String paymentRequestTitle(String name, String amount) {
    return '$name zahlt dir $amount';
  }

  @override
  String get paymentMethodBank => 'Überweisung';

  @override
  String get paymentMethodPaypal => 'PayPal';

  @override
  String paymentGiroCodeSemantics(String amount) {
    return 'GiroCode-QR-Code für eine Überweisung von $amount';
  }

  @override
  String get paymentGiroCodeHint =>
      'Mit der Banking-App scannen (GiroCode) – Name, IBAN und Betrag sind dann schon ausgefüllt.';

  @override
  String get paymentGiroCodeEuroOnly =>
      'Einen GiroCode gibt es nur für Euro – das Bankkonto:';

  @override
  String get paymentCopyIban => 'IBAN kopieren';

  @override
  String paymentPaypalQrSemantics(String amount) {
    return 'QR-Code des PayPal.me-Links über $amount';
  }

  @override
  String get paymentPaypalQrHint =>
      'Mit der Handykamera scannen – PayPal öffnet sich mit dem Betrag.';

  @override
  String get paymentShareLink => 'Link teilen';

  @override
  String get paymentRequestLocalNote =>
      'Deine Gruppen sehen diese Daten auch – ändern unter Einstellungen → Zahlungsdaten.';

  @override
  String get paymentDetailsLinkWarning =>
      'Auch Gruppen, die du per Einladungslink teilst, bekommen sie: Jede Person mit dem Link einer Gruppe kann sie lesen. Wenn du sie später änderst oder entfernst, bleiben frühere Kopien im Verlauf, in den Sicherungen und Wiederherstellungspunkten der anderen.';

  @override
  String paymentPayTitle(String name, String amount) {
    return 'Du zahlst $name $amount';
  }

  @override
  String paymentPaysTitle(String payer, String payee, String amount) {
    return '$payer zahlt $payee $amount';
  }

  @override
  String get paymentOpenPaypal => 'PayPal öffnen';

  @override
  String paymentSharedByNote(String name) {
    return '$name hat diese Daten mit der Gruppe geteilt.';
  }

  @override
  String paymentShowDetailsOf(String name) {
    return 'Zahlungsdaten von $name';
  }

  @override
  String get privacyPaymentTitle => 'Zahlungsdaten';

  @override
  String get privacyPaymentBody =>
      'Unter Einstellungen → Zahlungsdaten kannst du dein eigenes Bankkonto (Name auf dem Konto, IBAN, BIC) und deinen PayPal.me-Namen eintragen. MoneyLedger speichert sie auf diesem Gerät, für das Konto, das du nutzt (oder den lokalen Modus – sie ziehen mit um, wenn du ein Matrix-Konto verbindest), und trägt sie bei dir in jeder Gruppe ein, in der du bist, damit die anderen dir Geld zurückzahlen können: Sie bekommen sie wie den Rest der Gruppe – Ende-zu-Ende-verschlüsselt über Matrix und bei Gruppen, die du per Einladungslink teilst, in den verschlüsselten Kopien auf den Nostr-Relays, lesbar für jede Person mit dem Link dieser Gruppe. Gruppen, die es nur auf diesem Gerät gibt (lokaler Modus), bekommen nichts. Die Saldo-Seite zeigt sie als GiroCode oder PayPal.me-Link mit dem Betrag – auf deinem Bildschirm und auf dem von jemandem, der dir Geld schuldet. Wenn du sie in den Einstellungen entfernst oder änderst, werden deine Gruppen aktualisiert, frühere Kopien bleiben aber im Verlauf, in den Sicherungen und Wiederherstellungspunkten der anderen (und auf den Relays, bis sie ablaufen). In einer CSV sind sie nicht enthalten. Wenn du die lokalen Daten löschst oder die App deinstallierst, ist die Kopie auf diesem Gerät weg; beim Abmelden bleibt sie erhalten.';

  @override
  String get paymentDetailsPageTitle => 'Zahlungsdaten';

  @override
  String get payerSeveral => 'Mehrere Personen …';

  @override
  String get payersHint =>
      'Wer hat wie viel bezahlt? Wer nichts bezahlt hat, bleibt leer.';

  @override
  String paidByTwo(Object first, Object second) {
    return 'Bezahlt von $first und $second';
  }

  @override
  String paidByMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bezahlt von $count Personen',
    );
    return '$_temp0';
  }

  @override
  String get notificationsTitle => 'Benachrichtigungen';

  @override
  String get notificationsBody =>
      'Melden, wenn andere Ausgaben oder Zahlungen eintragen, ändern oder löschen (geprüft bei der Hintergrund-Synchronisierung).';

  @override
  String get notificationsNeedBackgroundSync =>
      'Braucht die Hintergrund-Synchronisierung – schalte sie oben ein.';

  @override
  String get notificationsBlocked =>
      'Benachrichtigungen sind für MoneyLedger blockiert – erlaube sie in den App-Einstellungen von Android.';

  @override
  String get notificationChannelName => 'Änderungen anderer';

  @override
  String get notificationChannelDescription =>
      'Wenn jemand in deinen Gruppen eine Ausgabe oder Zahlung einträgt, ändert oder löscht.';

  @override
  String get notifySomeone => 'Jemand';

  @override
  String get notifyAnExpense => 'eine Ausgabe';

  @override
  String notifyExpenseAdded(String name, String what, String amount) {
    return '$name hat $what eingetragen · $amount';
  }

  @override
  String notifyExpenseEdited(String name, String what) {
    return '$name hat $what geändert';
  }

  @override
  String notifyExpenseDeleted(String name, String what) {
    return '$name hat $what gelöscht';
  }

  @override
  String notifyPaymentAdded(
    String name,
    String from,
    String to,
    String amount,
  ) {
    return '$name hat eine Zahlung eingetragen: $from → $to · $amount';
  }

  @override
  String notifyPaymentEdited(String name, String from, String to) {
    return '$name hat eine Zahlung geändert: $from → $to';
  }

  @override
  String notifyPaymentDeleted(String name, String from, String to) {
    return '$name hat eine Zahlung gelöscht: $from → $to';
  }

  @override
  String notifySeveralChanges(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen von $names',
      one: '1 Änderung von $names',
    );
    return '$_temp0';
  }

  @override
  String notifyAddedToGroup(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Du wurdest zu dieser Gruppe hinzugefügt – $count Einträge.',
      one: 'Du wurdest zu dieser Gruppe hinzugefügt – 1 Eintrag.',
      zero: 'Du wurdest zu dieser Gruppe hinzugefügt.',
    );
    return '$_temp0';
  }

  @override
  String linkReplacedBanner(String name) {
    return '$name hat den Einladungslink dieser Gruppe ersetzt. Frag jemanden aus der Gruppe nach dem neuen Link und öffne ihn hier – bis dahin bekommst du die Änderungen von $name nicht.';
  }

  @override
  String get linkReplacedBannerNoName =>
      'Der Einladungslink dieser Gruppe wurde ersetzt. Frag jemanden aus der Gruppe nach dem neuen Link und öffne ihn hier – bis dahin verpasst du vielleicht Änderungen.';

  @override
  String get linkReplacedBannerMe =>
      'Du hast den Einladungslink dieser Gruppe auf einem anderen Gerät ersetzt. Öffne den neuen Link auch hier, damit weiter synchronisiert wird.';

  @override
  String get joinLinkReplacedTitle => 'Dieser Einladungslink wurde ersetzt';

  @override
  String get joinLinkReplacedBody =>
      'Die Gruppe hat einen neuen Einladungslink. Bitte jemanden aus der Gruppe, ihn dir zu schicken.';

  @override
  String get joinLinkPickReplaced =>
      'Jemand hat diesen Einladungslink ersetzt – du bekommst vielleicht nur eine alte Kopie. Frag lieber jemanden aus der Gruppe nach dem neuen Link.';

  @override
  String get joinLinkSwitchReplaced =>
      'Dieser Link wurde durch einen neueren ersetzt – wahrscheinlich ist es der alte. Behalte lieber deinen jetzigen Link.';
}
