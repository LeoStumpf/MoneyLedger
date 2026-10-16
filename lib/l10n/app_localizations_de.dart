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
  String failedWithError(Object error) {
    return 'Fehlgeschlagen: $error';
  }

  @override
  String errorWithDetail(Object error) {
    return 'Fehler: $error';
  }

  @override
  String get groupsTitle => 'Gruppen';

  @override
  String get importCsvTooltip => 'CSV importieren';

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
      'Deine Gruppen und Ausgaben bleiben auf diesem Gerät und sind wieder da, wenn du dich erneut mit diesem Konto anmeldest. Solange du abgemeldet bist, synchronisiert dieses Gerät nicht – Änderungen anderer Mitglieder kommen an, sobald du dich wieder anmeldest.';

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
  String get syncSettingsTitle => 'Synchronisierung';

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
  String get aboutTitle => 'Über MoneyLedger';

  @override
  String get somethingWentWrong => 'Etwas ist schiefgelaufen';

  @override
  String get signOutAndRestart => 'Abmelden und neu starten';

  @override
  String get expensesTitle => 'Ausgaben';

  @override
  String get addMember => 'Mitglied hinzufügen';

  @override
  String get membersTitle => 'Mitglieder';

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
    return '„$description“ wird für alle Mitglieder entfernt.';
  }

  @override
  String get deleteSettlementTitle => 'Zahlung löschen?';

  @override
  String deleteSettlementBody(Object from, Object to, Object amount) {
    return '„$from hat $to $amount gezahlt“ wird für alle Mitglieder entfernt und der Saldo wiederhergestellt.';
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
  String get syncedWithAll => 'Mit allen Mitgliedern synchronisiert';

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
      'Andere Mitglieder waren nicht erreichbar. Deine Änderungen sind auf diesem Gerät gespeichert und werden synchronisiert, sobald die Verbindung wieder steht.';

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
  String get splitExact => 'Genau';

  @override
  String get splitShares => 'Anteile';

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
  String splitRemaining(Object amount) {
    return 'Verbleibend: $amount';
  }

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
    return '„$group“ wird von diesem Gerät entfernt, und die anderen Mitglieder sehen, dass du gegangen bist. Deine Ausgaben bleiben in ihrem Kassenbuch.';
  }

  @override
  String deleteGroupBody(Object group) {
    return '„$group“ und alle Ausgaben darin werden dauerhaft von diesem Gerät entfernt.';
  }

  @override
  String get exportBackupTip => 'Tipp: Exportiere vorher eine CSV-Sicherung.';

  @override
  String get exportBackupFirst => 'Vorher CSV-Sicherung exportieren';

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
  String get noMembers => 'Keine Mitglieder.';

  @override
  String get formerMembers => 'Ehemalige Mitglieder';

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
    return '$matrixId · ehemaliges Mitglied';
  }

  @override
  String get formerMemberLocal => 'Lokal · ehemaliges Mitglied';

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
    return '$name aus dieser Gruppe entfernen?\n\nDer Ausgabenverlauf bleibt erhalten, nur die Mitgliedschaft wird beendet.';
  }

  @override
  String get remove => 'Entfernen';

  @override
  String get onboardingWelcome => 'Willkommen bei MoneyLedger';

  @override
  String get onboardingTagline => 'Ausgaben teilen – ohne Mittelsmann.';

  @override
  String get onboardingLocalTitle => 'Deine Daten bleiben auf deinem Gerät';

  @override
  String get onboardingLocalBody =>
      'Gruppen, Ausgaben und Salden werden lokal gespeichert – es gibt keinen zentralen MoneyLedger-Server, der deine Finanzen verwaltet.';

  @override
  String get onboardingSyncTitle =>
      'Mitglieder synchronisieren direkt untereinander';

  @override
  String get onboardingSyncBody =>
      'Änderungen werden direkt zwischen den Mitgliedern über Ende-zu-Ende-verschlüsselte Matrix-Nachrichten geteilt. Der Homeserver leitet nur verschlüsselte Daten weiter. Geräte synchronisieren, solange die App läuft, und unter Android regelmäßig im Hintergrund.';

  @override
  String get onboardingAddTitle => 'Füge alle hinzu – mit oder ohne Matrix';

  @override
  String get onboardingAddBody =>
      'Lade Leute über ihre Matrix-ID ein oder füge lokale Personen mit Namen hinzu und verknüpfe später ein Konto.';

  @override
  String get getStarted => 'Los geht\'s';

  @override
  String get devicesTitle => 'Geräte';

  @override
  String couldNotLoadDevices(Object error) {
    return 'Geräte konnten nicht geladen werden: $error';
  }

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
  String get authOfflineTitle => 'Keine Internetverbindung';

  @override
  String get authOfflineHint =>
      'Prüfe deine Verbindung und versuche es erneut.';

  @override
  String authUnreachableTitle(Object host) {
    return '$host ist nicht erreichbar';
  }

  @override
  String get authUnreachableHint =>
      'Prüfe die Homeserver-Adresse und deine Internetverbindung.';

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
  String get homeserverHint => 'matrix.org oder mozilla.modular.im';

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
      'MoneyLedger ist eine App zum Teilen von Ausgaben ohne zentralen Server. Sie hat kein eigenes Kontosystem – du meldest dich mit deinem Matrix-Konto an –, zeigt keine Werbung, enthält keine Analyse- oder Tracking-Funktionen und verkauft oder teilt deine Daten nicht. MoneyLedger wird von Leo Stumpf veröffentlicht, einem einzelnen Entwickler. Es gibt keinen MoneyLedger-Server, der deine Daten empfangen könnte.';

  @override
  String get privacyLedgerTitle => 'Dein Kassenbuch bleibt auf deinen Geräten';

  @override
  String get privacyLedgerBody =>
      'Gruppen, Personen, Ausgaben und Zahlungen werden nur in einer lokalen Datenbank auf jedem Gerät gespeichert, das mit dem Konto eines Mitglieds angemeldet ist. Jedes Mitglied einer Gruppe hat eine Kopie ihres Kassenbuchs – so funktioniert das Teilen: Namen, Matrix-IDs, Ausgaben und Zahlungen einer Gruppe sind für alle ihre Mitglieder sichtbar.';

  @override
  String get privacyHomeserverTitle => 'Was dein Matrix-Homeserver sieht';

  @override
  String get privacyHomeserverBody =>
      'Zum Synchronisieren sendet MoneyLedger jede Änderung als Ende-zu-Ende-verschlüsselte Matrix-Nachricht (to-device) an die Geräte der anderen Mitglieder. Dein Homeserver (und die Homeserver der anderen Mitglieder) leiten diese Nachrichten weiter und halten sie bis zur Zustellung vor, können sie aber nicht lesen. Sie sehen allerdings Metadaten: welche Konten und Geräte Nachrichten austauschen, wann, wie oft und ungefähr wie groß. Dein Matrix-Konto selbst – Benutzername, Geräte, Schlüssel, IP-Adressen und Anmeldeverlauf – verarbeitet dein Homeserver nach seiner eigenen Datenschutzerklärung.';

  @override
  String get privacyNoTrackingTitle => 'Keine Analyse, keine eigenen Server';

  @override
  String get privacyNoTrackingBody =>
      'Die App kommuniziert nur mit deinem Homeserver – und, wenn du Single Sign-on nutzt oder dich im Web registrierst, mit den Seiten, zu denen dich dein Homeserver im Browser schickt. Es gibt keine Analyse, keine Absturzberichte, keine Werbe-ID und keinerlei Tracking.';

  @override
  String get privacyBackgroundTitle =>
      'Hintergrund-Synchronisierung unter Android';

  @override
  String get privacyBackgroundBody =>
      'Unter Android kann MoneyLedger etwa alle 15 Minuten synchronisieren, während die App geschlossen ist (nur mit Netzwerkverbindung und nicht bei niedrigem Akku). Dafür werden dieselben verschlüsselten Nachrichten an deinen Homeserver genutzt; es werden keine Benachrichtigungen angezeigt. Du kannst das in den Einstellungen abschalten. Die Web-Version synchronisiert nur, solange ihr Tab geöffnet ist.';

  @override
  String get privacyCsvTitle => 'CSV-Export und -Import';

  @override
  String get privacyCsvBody =>
      'Beim Export einer Gruppe entsteht eine CSV-Datei mit ihren Ausgaben, den Namen der Personen und den Beträgen – nur, wenn du das auslöst. Wohin die Datei geht, entscheidest du; sie ist nicht verschlüsselt, und MoneyLedger hat danach keinen Einblick mehr. Beim Import wird nur die Datei gelesen, die du auswählst.';

  @override
  String get privacyBackupTitle => 'Gerätesicherungen';

  @override
  String get privacyBackupBody =>
      'Die automatische App-Sicherung von Android ist nicht abgeschaltet. Wenn Sicherungen auf deinem Telefon aktiviert sind, können die lokalen Daten der App (dein Kassenbuch und deine Matrix-Sitzung) nach den Regeln von Android in der Gerätesicherung in deinem Google-Konto landen.';

  @override
  String get privacyDeleteTitle => 'Deine Daten löschen';

  @override
  String get privacyDeleteBody =>
      '• Gruppe verlassen oder löschen (Gruppenmenü ⋮): Sie wird samt allen Einträgen von diesem Gerät entfernt. Wenn du sie verlässt, erfahren die anderen Mitglieder davon.\n• Beim Abmelden bleibt das Kassenbuch dieses Kontos auf dem Gerät, damit es bei der nächsten Anmeldung wieder da ist.\n• Wenn du die App deinstallierst (oder ihren Speicher löschst), wird alles entfernt, was sie auf dem Gerät gespeichert hat.\n• Kopien auf den Geräten anderer Mitglieder gehören ihnen: Sie behalten den Verlauf der Gruppe, einschließlich deiner Ausgaben darin.\n• Dein Matrix-Konto kannst du über deinen Homeserver deaktivieren.';

  @override
  String get privacyContactTitle => 'Kontakt';

  @override
  String get privacyContactBody =>
      'Fragen oder etwas, das hier nicht stimmt: Eröffne ein Issue unter https://github.com/LeoStumpf/MoneyLedger oder schreib an leo.m.stumpf@gmail.com.';
}
