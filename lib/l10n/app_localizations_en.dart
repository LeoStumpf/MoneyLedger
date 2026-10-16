// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MoneyLedger';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get ok => 'OK';

  @override
  String get done => 'Done';

  @override
  String get required => 'Required';

  @override
  String failedWithError(Object error) {
    return 'Failed: $error';
  }

  @override
  String errorWithDetail(Object error) {
    return 'Error: $error';
  }

  @override
  String get groupsTitle => 'Groups';

  @override
  String get importCsvTooltip => 'Import CSV';

  @override
  String get devicesTooltip => 'Devices & security';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get signOut => 'Sign out';

  @override
  String get newGroup => 'New group';

  @override
  String get signOutConfirmTitle => 'Sign out?';

  @override
  String get signOutConfirmBody =>
      'Your groups and expenses stay on this device and are back when you sign in again with this account. While signed out, this device doesn\'t sync — other members\' changes arrive once you sign back in.';

  @override
  String importFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String importedExpenses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count expenses',
      one: 'Imported 1 expense',
    );
    return '$_temp0';
  }

  @override
  String get noGroupsYet => 'No groups yet.\nCreate one to get started.';

  @override
  String get restoringGroupsTitle =>
      'Restoring your groups from your other devices…';

  @override
  String get restoringGroupsBody =>
      'Open MoneyLedger on another device signed in to this account — it sends your groups while the app is running there.';

  @override
  String get syncSettingsTitle => 'Sync';

  @override
  String get syncSettingsBody =>
      'Devices exchange changes while MoneyLedger is open. Changes from others wait on your homeserver (encrypted) until this device picks them up.';

  @override
  String get backgroundSyncTitle => 'Background sync';

  @override
  String get backgroundSyncBody =>
      'Also sync about every 15 minutes while the app is closed (with network, not on low battery).';

  @override
  String get noBackgroundSyncTitle => 'No background sync here';

  @override
  String get noBackgroundSyncBody =>
      'In the browser, MoneyLedger syncs only while this tab is open. The Android app also syncs periodically in the background.';

  @override
  String backgroundSyncScheduleFailed(String error) {
    return 'Background sync couldn\'t be set up on this device: $error';
  }

  @override
  String get encryptionUnavailableBanner =>
      'Encryption couldn\'t be started on this device, so syncing with other people and devices is off. Your groups stay available here. Restart the app; if this persists, reinstall or update it.';

  @override
  String get aboutTitle => 'About MoneyLedger';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get signOutAndRestart => 'Sign out and restart';

  @override
  String get expensesTitle => 'Expenses';

  @override
  String get addMember => 'Add member';

  @override
  String get membersTitle => 'Members';

  @override
  String get balanceTitle => 'Balance';

  @override
  String get moreTooltip => 'More';

  @override
  String get editGroup => 'Edit group';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get leaveGroup => 'Leave group';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String get addExpense => 'Add expense';

  @override
  String get removedFromGroupBanner =>
      'You were removed from this group. Its history stays readable here.';

  @override
  String get deleteFromThisDevice => 'Delete from this device';

  @override
  String get addedToGroupBanner =>
      'You\'ve been added to this group. Which participant are you?';

  @override
  String get choose => 'Choose';

  @override
  String get noExpensesYet => 'No expenses yet.';

  @override
  String get thisGroup => 'This group';

  @override
  String youLeftGroup(Object group) {
    return 'You left \"$group\"';
  }

  @override
  String deletedGroup(Object group) {
    return 'Deleted \"$group\"';
  }

  @override
  String exportFailed(Object error) {
    return 'Export failed: $error';
  }

  @override
  String exportedFile(Object fileName) {
    return 'Exported $fileName';
  }

  @override
  String get whichParticipantAreYou => 'Which participant are you?';

  @override
  String get imSomeoneNew => 'I\'m someone new';

  @override
  String get yourName => 'Your name';

  @override
  String get nameLabel => 'Name';

  @override
  String get join => 'Join';

  @override
  String get deleteExpenseTitle => 'Delete expense?';

  @override
  String deleteExpenseBody(Object description) {
    return '\"$description\" will be removed for all members.';
  }

  @override
  String get deleteSettlementTitle => 'Delete settlement?';

  @override
  String deleteSettlementBody(Object from, Object to, Object amount) {
    return '\"$from paid $to $amount\" will be removed for all members and the balance restored.';
  }

  @override
  String get matrixIdLabel => 'Matrix ID';

  @override
  String addedMember(Object userId) {
    return 'Added $userId';
  }

  @override
  String get syncProblemTooltip => 'Sync problem — tap for details';

  @override
  String get syncedWithAll => 'Synced with all members';

  @override
  String peerHasNoDevice(Object peer) {
    return '$peer has no active device — will sync when they sign in';
  }

  @override
  String waitingForPeer(Object peer) {
    return 'Waiting for $peer…';
  }

  @override
  String get syncProblemTitle => 'Sync problem';

  @override
  String get syncProblemBody =>
      'Could not reach other members. Your changes are saved on this device and will sync once the connection recovers.';

  @override
  String lastSynced(Object ago) {
    return 'Last synced $ago';
  }

  @override
  String lastError(Object error) {
    return 'Last error: $error';
  }

  @override
  String get retryingSync => 'Retrying sync…';

  @override
  String get retryNow => 'Retry now';

  @override
  String get agoJustNow => 'just now';

  @override
  String agoMinutes(int n) {
    return '$n min ago';
  }

  @override
  String agoHours(int n) {
    return '$n h ago';
  }

  @override
  String agoDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String paidByName(Object name) {
    return 'Paid by $name';
  }

  @override
  String get expenseOptions => 'Expense options';

  @override
  String settlementTitle(Object from, Object to) {
    return '$from paid $to';
  }

  @override
  String settlementSubtitle(Object date) {
    return 'Settlement · $date';
  }

  @override
  String get settlementOptions => 'Settlement options';

  @override
  String get editExpense => 'Edit expense';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get amountLabel => 'Amount';

  @override
  String get invalidNumber => 'Invalid number';

  @override
  String get currencyLabel => 'Currency';

  @override
  String get paidByLabel => 'Paid by';

  @override
  String get splitEqual => 'Equal';

  @override
  String get splitExact => 'Exact';

  @override
  String get splitShares => 'Shares';

  @override
  String get splitSelectAtLeastOne => 'Select at least one participant';

  @override
  String splitEquallyAmong(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Split equally among $n',
      one: 'Split equally among 1',
    );
    return '$_temp0';
  }

  @override
  String get splitAddsUpToTotal => 'Adds up to the total';

  @override
  String splitRemaining(Object amount) {
    return 'Remaining: $amount';
  }

  @override
  String get splitByWeight => 'Split by weight';

  @override
  String get splitEnterWeight => 'Enter at least one weight';

  @override
  String get splitAddsUpTo100 => 'Adds up to 100%';

  @override
  String get splitPercentMustTotal100 => 'Percentages must total 100%';

  @override
  String get recordPayment => 'Record payment';

  @override
  String get allSettledUp => 'All settled up!';

  @override
  String owesName(Object name) {
    return 'owes $name';
  }

  @override
  String get paymentRecorded => 'Payment recorded';

  @override
  String get paymentFromLabel => 'From (paid)';

  @override
  String get paymentToLabel => 'To (received)';

  @override
  String paymentExceedsDebt(Object amount) {
    return 'More than the $amount owed';
  }

  @override
  String get record => 'Record';

  @override
  String unsettledYouOwe(Object amount) {
    return 'You still owe $amount.';
  }

  @override
  String unsettledYouAreOwed(Object amount) {
    return 'You are still owed $amount.';
  }

  @override
  String get leaveGroupTitle => 'Leave group?';

  @override
  String get deleteGroupTitle => 'Delete group?';

  @override
  String leaveGroupBody(Object group) {
    return '\"$group\" will be removed from this device and the other members will see that you left. Your expenses stay in their ledger.';
  }

  @override
  String deleteGroupBody(Object group) {
    return '\"$group\" and all its expenses will be permanently removed from this device.';
  }

  @override
  String get backupBeforeExitTip =>
      'Tip: back up all groups first (Settings → Back up all groups).';

  @override
  String get backupBeforeExit => 'Back up all groups first';

  @override
  String get leave => 'Leave';

  @override
  String get groupNameLabel => 'Group name';

  @override
  String get defaultCurrencyLabel => 'Default currency';

  @override
  String get defaultCurrencyHelper =>
      'Only applies to new expenses — existing expenses keep their currency.';

  @override
  String get create => 'Create';

  @override
  String get inviteByMatrixId => 'Invite by Matrix ID';

  @override
  String get addPerson => 'Add person';

  @override
  String get noMembers => 'No members.';

  @override
  String get formerMembers => 'Former members';

  @override
  String get invite => 'Invite';

  @override
  String invitedMember(Object userId) {
    return 'Invited $userId';
  }

  @override
  String get nameHint => 'e.g. Alex';

  @override
  String get matrixIdOptionalLabel => 'Matrix ID (optional)';

  @override
  String get matrixIdOptionalHint =>
      '@user:server — leave blank for a local person';

  @override
  String get invalidMatrixId => 'Invalid Matrix ID';

  @override
  String formerMemberClaimed(Object matrixId) {
    return '$matrixId · former member';
  }

  @override
  String get formerMemberLocal => 'Local · former member';

  @override
  String get you => 'You';

  @override
  String get readd => 'Re-add';

  @override
  String readdedMember(Object name) {
    return 'Re-added $name';
  }

  @override
  String get localParticipant => 'Local';

  @override
  String get options => 'Options';

  @override
  String get rename => 'Rename';

  @override
  String get detachMatrixAccount => 'Detach Matrix account';

  @override
  String get linkMatrixAccount => 'Link Matrix account';

  @override
  String get removeFromGroup => 'Remove from group';

  @override
  String removeMemberBody(Object name) {
    return 'Remove $name from this group?\n\nTheir expense history is kept; only their membership is cleared.';
  }

  @override
  String get remove => 'Remove';

  @override
  String get onboardingWelcome => 'Welcome to MoneyLedger';

  @override
  String get onboardingTagline => 'Split expenses without a middleman.';

  @override
  String get onboardingLocalTitle => 'Your data lives on your device';

  @override
  String get onboardingLocalBody =>
      'Groups, expenses and balances are stored locally — there is no central MoneyLedger server holding your finances.';

  @override
  String get onboardingSyncTitle => 'Members sync peer-to-peer';

  @override
  String get onboardingSyncBody =>
      'Changes are shared directly between members over end-to-end-encrypted Matrix messages. The homeserver only relays ciphertext. Devices sync while the app runs and, on Android, periodically in the background.';

  @override
  String get onboardingAddTitle => 'Add anyone — Matrix or not';

  @override
  String get onboardingAddBody =>
      'Invite people by their Matrix ID, or add local participants by name and link an account later.';

  @override
  String get getStarted => 'Get started';

  @override
  String get devicesTitle => 'Devices';

  @override
  String couldNotLoadDevices(Object error) {
    return 'Could not load devices: $error';
  }

  @override
  String get thisDevice => 'This device';

  @override
  String get verified => 'Verified';

  @override
  String get notVerified => 'Not verified';

  @override
  String get verify => 'Verify';

  @override
  String verifyDeviceTitle(Object device) {
    return 'Verify $device';
  }

  @override
  String get verifyCompareEmoji =>
      'Confirm these emoji appear in the same order on the other device.';

  @override
  String get deviceVerified => 'Device verified.';

  @override
  String get verificationFailed => 'Verification failed.';

  @override
  String verificationFailedWithError(Object error) {
    return 'Verification failed: $error.';
  }

  @override
  String get emojiNoMatch => 'They don\'t match';

  @override
  String get emojiMatch => 'They match';

  @override
  String get onlyDevice => 'This is your only device.';

  @override
  String get allDevicesVerified => 'All your devices are verified.';

  @override
  String devicesNeedVerification(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices need verification.',
      one: '1 device needs verification.',
    );
    return '$_temp0';
  }

  @override
  String get authOfflineTitle => 'No internet connection';

  @override
  String get authOfflineHint => 'Check your connection and try again.';

  @override
  String authUnreachableTitle(Object host) {
    return 'Can\'t reach $host';
  }

  @override
  String get authUnreachableHint =>
      'Check the homeserver address and your internet connection.';

  @override
  String get authTimeoutTitle => 'The server took too long to respond';

  @override
  String get authTimeoutHint => 'Check your connection and try again.';

  @override
  String authNotAHomeserverTitle(Object host) {
    return '$host doesn\'t look like a Matrix homeserver';
  }

  @override
  String get authNotAHomeserverHint =>
      'Check the address — for example matrix.org.';

  @override
  String get authWrongCredentialsTitle => 'Wrong username or password';

  @override
  String get authWrongCredentialsHint => 'Check both and try again.';

  @override
  String get authDeactivatedTitle => 'This account has been deactivated';

  @override
  String get authDeactivatedHint =>
      'Contact your homeserver administrator, or use another account.';

  @override
  String get authRateLimitedTitle => 'Too many attempts';

  @override
  String authRateLimitedRetry(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Please wait $seconds seconds and try again.',
      one: 'Please wait 1 second and try again.',
    );
    return '$_temp0';
  }

  @override
  String get authRateLimitedHint => 'Please wait a moment and try again.';

  @override
  String get authSsoTokenTitle => 'Sign-in link expired or invalid';

  @override
  String get authSsoTokenHint => 'Please start the sign-in again.';

  @override
  String get authUsernameTakenTitle => 'That username is already taken';

  @override
  String get authUsernameTakenHint => 'Choose a different username.';

  @override
  String get authInvalidUsernameTitle => 'That username isn\'t allowed';

  @override
  String get authInvalidUsernameHint =>
      'Use only lowercase letters, digits and . _ = - /';

  @override
  String get authWeakPasswordTitle => 'Password is too weak';

  @override
  String get authWeakPasswordHint =>
      'Use a longer password with a mix of letters, digits and symbols.';

  @override
  String get authRegistrationDisabledTitle =>
      'This homeserver doesn\'t allow sign-up here';

  @override
  String get authRegistrationDisabledHint =>
      'Create your account on its website, then sign in.';

  @override
  String get authUnknownTitle => 'Something went wrong';

  @override
  String get authUnknownHint => 'Please try again. The details below may help.';

  @override
  String get authErrorDetails => 'Details';

  @override
  String get signInSubtitle => 'Sign in with your Matrix account';

  @override
  String get homeserverLabel => 'Homeserver';

  @override
  String get homeserverHint => 'matrix.org or mozilla.modular.im';

  @override
  String resolvedTo(Object url) {
    return 'Resolved to $url';
  }

  @override
  String continueWith(Object provider) {
    return 'Continue with $provider';
  }

  @override
  String get orDivider => 'or';

  @override
  String get matrixIdOrUsernameLabel => 'Matrix ID or username';

  @override
  String get passwordLabel => 'Password';

  @override
  String get signIn => 'Sign in';

  @override
  String get createAccountLink => 'New here? Create an account';

  @override
  String get createAccount => 'Create account';

  @override
  String get usernameLabel => 'Username';

  @override
  String get passwordMinLength => 'At least 8 characters';

  @override
  String get alreadyHaveAccount => 'Already have an account? Sign in';

  @override
  String get registerOnWebTitle => 'Register on the web';

  @override
  String registerOnWebBody(Object requirements) {
    return 'This homeserver requires $requirements, which MoneyLedger can\'t do in-app yet. Create your account on its website, then come back and sign in.';
  }

  @override
  String get openHomeserverWebsite => 'Open homeserver website';

  @override
  String listAnd(Object first, Object last) {
    return '$first and $last';
  }

  @override
  String get regReqExtraVerification => 'extra verification';

  @override
  String get regReqCaptcha => 'a CAPTCHA';

  @override
  String get regReqEmail => 'email verification';

  @override
  String get regReqPhone => 'phone verification';

  @override
  String get regReqTerms => 'accepting the terms of service';

  @override
  String get regReqToken => 'a registration token';

  @override
  String get regReqWebSignup => 'signing up on its own website';

  @override
  String get aboutAndPrivacy => 'About & privacy';

  @override
  String aboutVersion(Object version) {
    return 'Version $version';
  }

  @override
  String get aboutDescription =>
      'Split expenses with friends — decentralized and end-to-end encrypted over Matrix. Your ledger stays on your devices; there is no MoneyLedger server.';

  @override
  String get aboutSourceCode => 'Source code';

  @override
  String get aboutLicense => 'License';

  @override
  String aboutLicenseValue(Object license) {
    return '$license — free software: you may use, study, share and modify it.';
  }

  @override
  String aboutLegalese(Object license) {
    return '© Leo Stumpf. Licensed under the $license.';
  }

  @override
  String get aboutOpenSourceLicenses => 'Open-source licenses';

  @override
  String get privacyPolicyTitle => 'Privacy policy';

  @override
  String privacyLastUpdated(Object date) {
    return 'Last updated: $date';
  }

  @override
  String get privacyIntro =>
      'MoneyLedger is an expense-sharing app without a central server. It has no account system of its own — you sign in with your Matrix account — shows no ads, contains no analytics or tracking, and does not sell or share your data. MoneyLedger is published by Leo Stumpf, an individual developer. There is no MoneyLedger server that could receive your data.';

  @override
  String get privacyLedgerTitle => 'Your ledger stays on your devices';

  @override
  String get privacyLedgerBody =>
      'Groups, participants, expenses and payments are stored only in a local database on each device signed in to a member\'s account. Every member of a group has a copy of that group\'s ledger — that is how sharing works: the names, Matrix IDs, expenses and payments in a group are visible to all of its members.';

  @override
  String get privacyHomeserverTitle => 'What your Matrix homeserver sees';

  @override
  String get privacyHomeserverBody =>
      'To sync, MoneyLedger sends every change as an end-to-end-encrypted Matrix to-device message to the other members\' devices. Your homeserver (and the homeservers of the other members) relay these messages and queue them until they are delivered, but cannot read them. They do see metadata: which accounts and devices exchange messages, when, how often and roughly how large they are. Your Matrix account itself — user name, devices, encryption keys, IP addresses and sign-in history — is handled by your homeserver under its own privacy policy.';

  @override
  String get privacyNoTrackingTitle => 'No analytics, no servers of ours';

  @override
  String get privacyNoTrackingBody =>
      'The app only talks to your homeserver — and, if you use single sign-on or sign up on the web, to the pages your homeserver sends you to in your browser. There is no analytics, no crash reporting, no advertising ID and no tracking of any kind.';

  @override
  String get privacyBackgroundTitle => 'Background sync on Android';

  @override
  String get privacyBackgroundBody =>
      'On Android, MoneyLedger can sync about every 15 minutes while the app is closed (only with a network connection and not on low battery). It uses the same encrypted messages to your homeserver and shows no notifications. You can turn it off in Settings. The web version syncs only while its tab is open.';

  @override
  String get privacyCsvTitle => 'Export, backup and import';

  @override
  String get privacyCsvBody =>
      'Exporting a group writes a CSV file with its expenses, payments, the participants\' names and the amounts; a backup (\"Back up all groups\", or one group from its menu) writes one JSON file with the groups, including the participants\' Matrix IDs and deleted entries. Both happen only when you ask for it. Where the file goes is your choice. A CSV is always plain text; a backup is plain text too unless you set a passphrase — then it is encrypted on your device (Argon2id + AES-256-GCM) and can only be restored with that passphrase, which MoneyLedger never stores or sends anywhere. MoneyLedger has no visibility into the file afterwards. Importing or restoring reads only the file you pick.';

  @override
  String get privacyBackupTitle => 'Device backups';

  @override
  String get privacyBackupBody =>
      'MoneyLedger opts out of Android\'s automatic app backup and device-to-device transfer. Your ledger and your Matrix session (including its encryption keys) are never copied into a Google backup or onto another phone by Android. On a new device, sign in and your groups are restored from your other devices and the other members; for groups only you use, a backup file (Settings → Back up all groups) is your own offline copy.';

  @override
  String get privacyDeleteTitle => 'Deleting your data';

  @override
  String get privacyDeleteBody =>
      '• Leave or delete a group (group menu ⋮): it and all its records are removed from this device. When you leave, the other members are told that you left.\n• Signing out keeps this account\'s ledger on the device, so it is back when you sign in again.\n• Uninstalling the app (or clearing its storage) removes everything it stored on the device.\n• Copies on other members\' devices are theirs: they keep the group\'s history, including your expenses in it.\n• Your Matrix account can be deactivated through your homeserver.';

  @override
  String get privacyContactTitle => 'Contact';

  @override
  String get privacyContactBody =>
      'Questions, or anything that looks wrong here: open an issue at https://github.com/LeoStumpf/MoneyLedger or email leo.m.stumpf@gmail.com.';

  @override
  String youAreOwedAmount(String amount) {
    return 'You are owed $amount';
  }

  @override
  String youOweAmount(String amount) {
    return 'You owe $amount';
  }

  @override
  String get settledUp => 'Settled up';

  @override
  String get notParticipating => 'Not a participant';

  @override
  String lastActivity(String date) {
    return 'Last activity $date';
  }

  @override
  String get totalOwedLabel => 'You are owed';

  @override
  String get totalOwingLabel => 'You owe';

  @override
  String get totalNothing => 'Nothing';

  @override
  String get overallSettledUp => 'You\'re all settled up';

  @override
  String get overviewTitle => 'Across all groups';

  @override
  String get groupsEmptyTitle => 'No groups yet';

  @override
  String get groupsEmptyBody =>
      'Create a group for a trip, your flat or a dinner out — then add the people you share costs with.';

  @override
  String get createGroup => 'Create group';

  @override
  String get importCsv => 'Import CSV';

  @override
  String membersCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get youPaid => 'You paid';

  @override
  String youLentAmount(String amount) {
    return 'you lent $amount';
  }

  @override
  String youBorrowedAmount(String amount) {
    return 'you borrowed $amount';
  }

  @override
  String get notInvolved => 'not involved';

  @override
  String settlementYouPaid(String to) {
    return 'You paid $to';
  }

  @override
  String settlementPaidYou(String from) {
    return '$from paid you';
  }

  @override
  String get paymentLabel => 'Payment';

  @override
  String get yourBalance => 'Your balance';

  @override
  String get settleUp => 'Settle up';

  @override
  String get balancesButton => 'Balances';

  @override
  String get balancesSection => 'Balances';

  @override
  String get suggestedPayments => 'Suggested payments';

  @override
  String get suggestedPaymentsHint =>
      'Tap a payment once it has been made to record it.';

  @override
  String get balanceGetsBack => 'gets back';

  @override
  String get balanceOwes => 'owes';

  @override
  String get balanceYouGetBack => 'you get back';

  @override
  String get balanceYouOwe => 'you owe';

  @override
  String get balanceSettled => 'settled up';

  @override
  String debtPays(String from, String to) {
    return '$from pays $to';
  }

  @override
  String get allSettledUpBody => 'Nobody in this group owes anybody anything.';

  @override
  String get expensesEmptyTitle => 'No expenses yet';

  @override
  String get expensesEmptyBody =>
      'Add the first expense — MoneyLedger works out who owes whom.';

  @override
  String get splitSection => 'Split';

  @override
  String get nameOptionalHelper =>
      'Optional with a Matrix ID — their profile name is used';

  @override
  String get nameOrMatrixIdRequired => 'Enter a name or a Matrix ID';

  @override
  String get next => 'Next';

  @override
  String get skip => 'Skip';

  @override
  String get localPerson => 'Local person';

  @override
  String debtYouPay(String to) {
    return 'You pay $to';
  }

  @override
  String debtPaysYou(String from) {
    return '$from pays you';
  }

  @override
  String get backupSectionTitle => 'Backup';

  @override
  String get backupExportTitle => 'Back up all groups';

  @override
  String get backupExportBody =>
      'Saves every group — with payments and deleted entries — to one file, optionally encrypted with a passphrase. Without one the file is plain text: keep it somewhere safe.';

  @override
  String get backupRestoreTitle => 'Restore from backup';

  @override
  String get backupRestoreBody =>
      'Merges a backup file into this device. Newer entries win; nothing is duplicated.';

  @override
  String lastBackupAt(String date) {
    return 'Last backup: $date';
  }

  @override
  String get lastBackupNever => 'Last backup: never';

  @override
  String backupSaved(String fileName) {
    return 'Backup saved: $fileName';
  }

  @override
  String get backupNotABackup => 'This file is not a MoneyLedger backup.';

  @override
  String backupNewerVersion(int version) {
    return 'This backup was made by a newer version of MoneyLedger (format $version). Update the app to restore it.';
  }

  @override
  String get backupMalformed =>
      'This backup file is damaged and can\'t be restored.';

  @override
  String get restorePreviewTitle => 'Restore backup?';

  @override
  String restoreBackupFrom(String date) {
    return 'Backup from $date';
  }

  @override
  String restoreOtherAccount(String account) {
    return 'This backup was made by $account. Its groups will be added to the account you are signed in with.';
  }

  @override
  String groupsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groups',
      one: '1 group',
    );
    return '$_temp0';
  }

  @override
  String expensesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count expenses',
      one: '1 expense',
    );
    return '$_temp0';
  }

  @override
  String paymentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payments',
      one: '1 payment',
    );
    return '$_temp0';
  }

  @override
  String restoreNewGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new groups',
      one: '1 new group',
      zero: 'No new groups',
    );
    return '$_temp0';
  }

  @override
  String restoreChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries will be added or updated.',
      one: '1 entry will be added or updated.',
      zero: 'Everything in this backup is already on this device.',
    );
    return '$_temp0';
  }

  @override
  String get restoreTagNew => 'new';

  @override
  String get restoreTagLeft => 'left earlier — comes back';

  @override
  String restoreTagChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return '$_temp0';
  }

  @override
  String get restoreTagUpToDate => 'up to date';

  @override
  String get restoreLeftNote =>
      'Groups you left or deleted come back on this device. If the other members removed you from a group, it comes back read-only (history only) — a removal after this backup shows up at the next sync.';

  @override
  String get restoreAction => 'Restore';

  @override
  String restoredGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Restored $count groups',
      one: 'Restored 1 group',
    );
    return '$_temp0';
  }

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get backupNudgeTitle => 'Back up your groups';

  @override
  String backupNudgeBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count groups exist only on this device. If you lose it, they are gone — save a backup file.',
      one:
          '1 group exists only on this device. If you lose it, the group is gone — save a backup file.',
    );
    return '$_temp0';
  }

  @override
  String get backupNudgeLater => 'Later';

  @override
  String get backupNudgeAction => 'Back up now';

  @override
  String get onboardingBackupTitle => 'Keep a copy';

  @override
  String get onboardingBackupBody =>
      'Nobody else stores your ledger. Groups with other members are copied to their devices. For groups only you use, sign in on a second device too, or save a backup now and then (Settings → Back up all groups).';

  @override
  String get csvPreviewTitle => 'Import CSV?';

  @override
  String csvPreviewNewGroup(String name) {
    return 'Creates the new group “$name”.';
  }

  @override
  String csvPreviewExistingGroup(String name) {
    return 'Merges into your group “$name”. Newer entries win.';
  }

  @override
  String csvPreviewUnmatched(String names) {
    return 'Not found in the group — will be added as new people: $names';
  }

  @override
  String csvPreviewAmbiguous(String names) {
    return 'Several participants have the same name — the active one is used: $names';
  }

  @override
  String get csvImportAction => 'Import';

  @override
  String get csvImportEmpty => 'This CSV contains no expenses or payments.';

  @override
  String importedExpensesAndPayments(String expenses, String payments) {
    return 'Imported $expenses and $payments';
  }

  @override
  String recordAddedBy(String name) {
    return 'Added by $name';
  }

  @override
  String recordEditedBy(String name) {
    return 'Last edited by $name';
  }

  @override
  String recordRecordedBy(String name) {
    return 'Recorded by $name';
  }

  @override
  String get recordYou => 'you';

  @override
  String get recordUnsigned => 'Saved by an older app version (unsigned)';

  @override
  String get recordSigUnverified =>
      'Signature not verifiable — the signing device may have signed out';

  @override
  String get recordSigVerified =>
      'Verified on receipt against the device\'s key';

  @override
  String recordSigVouched(String name) {
    return 'Device confirmed by $name';
  }

  @override
  String recordSigConflict(String name) {
    return 'Signature doesn\'t match $name\'s device';
  }

  @override
  String get recordNotYourDevice =>
      'Claims to be from you, but not from one of your devices';

  @override
  String recordVersionRejected(String relay, String name) {
    return 'A newer version relayed by $relay was refused: it claims to be from $name but isn\'t validly signed by their device.';
  }

  @override
  String recordSignedByDevice(String device, String date) {
    return 'Signed by device $device · $date';
  }

  @override
  String get recordSignatureDetails => 'Signature details';

  @override
  String get recordSignatureWarning => 'Signature problem';

  @override
  String peerHasNoVerifiedDevice(Object peer) {
    return '$peer has no verified device — verify one to sync (only verified devices are synced)';
  }

  @override
  String get verifiedOnlyTitle => 'Only sync with verified devices';

  @override
  String get verifiedOnlyOffBody =>
      'Off: every device of your group members (and your own) receives your ledger data.';

  @override
  String get verifiedOnlyOnBody =>
      'On: devices you haven\'t verified by emoji comparison — yours or other members\' — receive nothing from this device.';

  @override
  String get verifiedOnlyConfirmTitle => 'Only sync with verified devices?';

  @override
  String get verifiedOnlyConfirmBody =>
      'Your expenses, payments and group changes will only be sent to devices you have verified by comparing emojis (Devices page for your own, the members page for others).\n\nUnverified devices — including a member\'s new phone or your own new login — get nothing until you verify them, so they fall behind. Records you receive are still accepted; the details show whether the signing device is verified.\n\nApplies to this device and account only.';

  @override
  String get verifiedOnlyTurnOn => 'Turn on';

  @override
  String memberUnverifiedDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unverified devices',
      one: '1 unverified device',
    );
    return '$_temp0';
  }

  @override
  String get memberNotReachableUnverified =>
      'Not reachable — no verified device';

  @override
  String memberDevicesTitle(Object name) {
    return 'Devices of $name';
  }

  @override
  String get memberDevicesBody =>
      'Verify a device by comparing emojis with its owner (in person or on a call). Verification is stored on this device only.';

  @override
  String get memberHasNoDevices => 'No active devices.';

  @override
  String get incomingVerificationTitle => 'Verification request';

  @override
  String incomingVerificationOwnDevice(Object device) {
    return 'Your device $device wants to verify this device by comparing emojis.';
  }

  @override
  String incomingVerificationMember(Object user, Object device) {
    return '$user (device $device) wants to verify this device by comparing emojis.';
  }

  @override
  String get accept => 'Accept';

  @override
  String get decline => 'Decline';

  @override
  String get recordDeviceVerifiedByYou =>
      'You verified this device (emoji comparison).';

  @override
  String get recordDeviceNotVerifiedByYou =>
      'You haven\'t verified this device (emoji comparison).';

  @override
  String get categoryLabel => 'Category';

  @override
  String get categoryFood => 'Food & drink';

  @override
  String get categoryGroceries => 'Groceries';

  @override
  String get categoryTransport => 'Transport';

  @override
  String get categoryAccommodation => 'Accommodation';

  @override
  String get categoryEntertainment => 'Entertainment';

  @override
  String get categoryShopping => 'Shopping';

  @override
  String get categoryHome => 'Home & utilities';

  @override
  String get categoryHealth => 'Health';

  @override
  String get categoryTravel => 'Travel';

  @override
  String get categoryOther => 'Other';

  @override
  String get noteLabel => 'Note (optional)';

  @override
  String get expenseHasNote => 'Has a note';

  @override
  String get searchTooltip => 'Search';

  @override
  String get searchHint => 'Search description, note, payer';

  @override
  String get closeSearch => 'Close search';

  @override
  String get filterInvolvingMe => 'Involving me';

  @override
  String get noMatchesTitle => 'Nothing found';

  @override
  String get noMatchesBody => 'Try another search or clear the filters.';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String filterResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0';
  }

  @override
  String get archiveGroup => 'Archive group';

  @override
  String get unarchiveGroup => 'Unarchive group';

  @override
  String archivedSection(int count) {
    return 'Archived ($count)';
  }

  @override
  String get archivedSectionHint =>
      'Only hidden on this device. A group comes back by itself when something new is added.';

  @override
  String groupArchived(String name) {
    return '“$name” archived';
  }

  @override
  String groupArchivedUnsettled(String name) {
    return '“$name” archived — your open balance still counts in the totals.';
  }

  @override
  String groupUnarchived(String name) {
    return '“$name” is back in your groups';
  }

  @override
  String get archivedBanner => 'This group is archived on this device.';

  @override
  String get undo => 'Undo';

  @override
  String get simplifyDebtsInfoTooltip => 'How are payments suggested?';

  @override
  String get simplifyDebtsInfoTitle => 'Simplified debts';

  @override
  String get simplifyDebtsInfoBody =>
      'MoneyLedger adds up all expenses and payments into one balance per person and suggests the fewest payments that settle everyone up. So you might pay someone you never shared an expense with directly — the amounts everyone pays and gets back stay exactly the same.\n\nEach currency is settled on its own: amounts are never converted.';

  @override
  String get simplifyDebtsPerCurrency =>
      'Settled separately per currency — amounts are never converted.';

  @override
  String get backupPassphraseTitle => 'Protect the backup?';

  @override
  String get backupPassphraseBody =>
      'You can encrypt the file with a passphrase. Leave it empty to save it unencrypted.';

  @override
  String get backupPassphraseLabel => 'Passphrase (optional)';

  @override
  String get backupPassphraseConfirmLabel => 'Repeat passphrase';

  @override
  String get backupPassphraseMismatch => 'The passphrases don\'t match';

  @override
  String get backupPassphraseWeak =>
      'Strength: weak — use a longer one, e.g. four random words';

  @override
  String get backupPassphraseFair => 'Strength: fair';

  @override
  String get backupPassphraseStrong => 'Strength: strong';

  @override
  String get backupPlaintextWarning =>
      'Without a passphrase the file is not encrypted: anyone who gets it can read all its groups.';

  @override
  String get backupPassphraseKeepSafe =>
      'Don\'t lose the passphrase — without it the backup can\'t be restored, and nobody can recover it.';

  @override
  String get backupEncrypting => 'Encrypting…';

  @override
  String get backupDecrypting => 'Decrypting…';

  @override
  String get backupUnlockTitle => 'Encrypted backup';

  @override
  String get backupUnlockBody =>
      'Enter the passphrase this backup was saved with.';

  @override
  String get backupUnlockLabel => 'Passphrase';

  @override
  String get backupUnlockAction => 'Unlock';

  @override
  String get backupWrongPassphrase =>
      'Wrong passphrase — or the file was changed. Try again.';

  @override
  String get backupSavedNoName => 'Backup saved';

  @override
  String backupSavedEncrypted(String fileName) {
    return 'Encrypted backup saved: $fileName';
  }

  @override
  String get backupSavedEncryptedNoName => 'Encrypted backup saved';

  @override
  String get exportedNoName => 'CSV exported';

  @override
  String get backupThisGroup => 'Back up this group';

  @override
  String get showPassphrase => 'Show passphrase';

  @override
  String get hidePassphrase => 'Hide passphrase';

  @override
  String get restoreEncryptedNote =>
      'Encrypted backup — unlocked with your passphrase.';

  @override
  String get restoreTagRemoved => 'read-only — you were removed';

  @override
  String restoreIncomplete(int count, String error) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count groups couldn\'t be restored and were left unchanged: $error',
      one: '1 group couldn\'t be restored and was left unchanged: $error',
    );
    return '$_temp0';
  }

  @override
  String get legacyRefusedTitle => 'Some data couldn\'t be received';

  @override
  String legacyRefusedBody(int count, String sender, String group) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$sender sent $count entries of “$group” that were saved by an older app version without a signature. They were refused, so the group is incomplete or missing here. Ask $sender to recreate the group.',
      one:
          '$sender sent 1 entry of “$group” that was saved by an older app version without a signature. It was refused, so the group is incomplete or missing here. Ask $sender to recreate the group.',
    );
    return '$_temp0';
  }
}
