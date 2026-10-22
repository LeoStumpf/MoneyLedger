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
  String get groupsTitle => 'Groups';

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
      'Your groups and expenses stay on this device and are back when you sign in again with this account. While signed out, this device doesn\'t sync — other people\'s changes arrive once you sign back in.';

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
  String get addMember => 'Add person';

  @override
  String get membersTitle => 'People';

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
      'You\'ve been added to this group. Which person are you?';

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
  String exportedFile(Object fileName) {
    return 'Exported $fileName';
  }

  @override
  String get whichParticipantAreYou => 'Which person are you?';

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
    return '\"$description\" will be removed for everyone in the group.';
  }

  @override
  String get deleteSettlementTitle => 'Delete settlement?';

  @override
  String deleteSettlementBody(Object from, Object to, Object amount) {
    return '\"$from paid $to $amount\" will be removed for everyone in the group and the balance restored.';
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
  String get syncedWithAll => 'Synced with everyone in the group';

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
      'Could not reach the others in the group. Your changes are saved on this device and will sync once the connection recovers.';

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
  String get splitEqual => 'Equally';

  @override
  String get splitExact => 'Amounts';

  @override
  String get splitShares => 'Shares';

  @override
  String get splitPercent => 'Percent';

  @override
  String get splitSelectAtLeastOne => 'Select at least one person';

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
  String splitLeft(Object amount) {
    return '$amount left';
  }

  @override
  String splitTooMuch(Object amount) {
    return '$amount too much';
  }

  @override
  String splitPercentValue(Object value) {
    return '$value%';
  }

  @override
  String get splitEnterAmountFirst => 'Enter the amount first';

  @override
  String get splitDistribute => 'Distribute';

  @override
  String get splitRescale => 'Rescale proportionally';

  @override
  String get splitSetTotalToSum => 'Set total to the sum';

  @override
  String splitTotalSetTo(String amount) {
    return 'Total set to $amount';
  }

  @override
  String get splitFineTuneAsAmounts => 'Fine-tune as amounts';

  @override
  String get splitPutRestHere => 'Put the rest here';

  @override
  String get splitShareMore => 'One share more';

  @override
  String get splitShareLess => 'One share less';

  @override
  String get splitOpenFieldsHint =>
      'Empty fields share the rest · 0 = not involved';

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
  String get edit => 'Edit';

  @override
  String get editPayment => 'Edit payment';

  @override
  String get paymentUpdated => 'Payment updated';

  @override
  String get paymentGone =>
      'This payment was deleted in the meantime — nothing was changed.';

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
    return '\"$group\" will be removed from this device and the others in the group will see that you left. Your expenses stay in their ledger.';
  }

  @override
  String deleteGroupBody(Object group) {
    return '\"$group\" and all its expenses will be permanently removed from this device.';
  }

  @override
  String get backupBeforeExitTip =>
      'Tip: back up all groups first (Settings → Backup & restore).';

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
  String get noMembers => 'Nobody in this group yet.';

  @override
  String get formerMembers => 'No longer in the group';

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
    return '$matrixId · no longer in the group';
  }

  @override
  String get formerMemberLocal => 'Local · no longer in the group';

  @override
  String get formerMemberTag => 'no longer in the group';

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
    return 'Remove $name from this group?\n\nTheir expense history is kept; they are just no longer in the group.';
  }

  @override
  String get remove => 'Remove';

  @override
  String get onboardingAddTitle => 'Add anyone — Matrix or not';

  @override
  String get onboardingAddBody =>
      'Invite people by their Matrix ID, or add them by name only and link an account later.';

  @override
  String get getStarted => 'Get started';

  @override
  String get devicesTitle => 'Devices';

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
  String authUnreachableTitle(Object host) {
    return 'Can\'t reach $host';
  }

  @override
  String get authUnreachableHint =>
      'The server may be down or the address mistyped — or you\'re offline. Check the homeserver address and your internet connection.';

  @override
  String get authUnreachableNoHostTitle => 'Can\'t reach the server';

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
  String get homeserverHint => 'e.g. matrix.org';

  @override
  String get checkServerTooltip => 'Check server';

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
      'MoneyLedger is an expense-sharing app without a central server. It has no account system of its own — you sign in with your Matrix account, or use the app without any account (local mode) — shows no ads, contains no analytics or tracking, and does not sell or share your data. MoneyLedger is published by Leo Stumpf, an individual developer. There is no MoneyLedger server that could receive your data.';

  @override
  String get privacyLedgerTitle => 'Your ledger stays on your devices';

  @override
  String get privacyLedgerBody =>
      'Groups, people, expenses and payments are stored only in a local database on each device signed in to the account of someone in the group. Everyone in a group has a copy of that group\'s ledger — that is how sharing works: the names, Matrix IDs, expenses and payments in a group are visible to everyone in it.';

  @override
  String get privacyHomeserverTitle => 'What your Matrix homeserver sees';

  @override
  String get privacyHomeserverBody =>
      'To sync, MoneyLedger sends every change as an end-to-end-encrypted Matrix to-device message to the devices of the others in the group. Your homeserver (and their homeservers) relay these messages and keep each one only until the receiving device has fetched it, but cannot read them. They do see metadata: which accounts and devices exchange messages, when, how often and roughly how large they are. MoneyLedger creates no rooms, saves nothing in your account\'s settings and never marks you as online; when it syncs, it asks your homeserver only for these messages and for encryption-key updates — not for your rooms, presence or account settings. What your homeserver still keeps is what every Matrix app needs: your account, its list of devices (this one is named “MoneyLedger”, with when and from which IP address it was last used), each device\'s public encryption keys and one-time keys, and the messages above until they are delivered (for a device that never comes back, until it is removed). Your Matrix account itself — user name, devices, encryption keys, IP addresses and sign-in history — is handled by your homeserver under its own privacy policy.';

  @override
  String get privacyNoTrackingTitle => 'No analytics, no servers of ours';

  @override
  String get privacyNoTrackingBody =>
      'Apart from the Nostr relays of groups you share with an invite link (see “Shared groups (invite link)”) and the exchange-rate service you can ask with “Fetch current rate” (see “Exchange rates”), the app talks only to Matrix homeservers: on the sign-in page to the server you enter — and only once you confirm it or sign in — and after that only to your own homeserver. Through it, the app also looks up the Matrix profile names and devices of the people in your groups (your homeserver may ask theirs). If you use single sign-on or sign up on the web, your browser opens the pages your homeserver sends you to (for matrix.org possibly Element\'s sign-up page, app.element.io). Links in the app — to the source code on GitHub, for example — open in your browser only when you tap them. The web version is loaded entirely from the site that hosts it: no code or fonts from Google or any other third party. There is no analytics, no crash reporting, no advertising ID and no tracking of any kind.';

  @override
  String get privacyBackgroundTitle => 'Background sync on Android';

  @override
  String get privacyBackgroundBody =>
      'On Android, MoneyLedger can sync about every 15 minutes while the app is closed (only with a network connection and not on low battery). It uses the same encrypted messages to your homeserver and, for groups you share with an invite link, the same encrypted copies on the Nostr relays (also without an account). When it finds expenses or payments that someone else added, changed or deleted, it shows a notification with the group\'s name, who did it, the description and the amount (on by default; Settings → Sync → Notifications). These notifications are made on the device itself — no push service, no Google or Firebase, nothing is sent for them — and on the lock screen they follow Android\'s setting for sensitive content. With a Matrix account you can turn background sync off in Settings; without one it runs only while you have a group shared with an invite link. The web version syncs only while its tab is open and shows no notifications.';

  @override
  String get privacyCsvTitle => 'Export, backup and import';

  @override
  String get privacyCsvBody =>
      'Exporting a group writes a CSV file with its expenses, payments, the people\'s names and the amounts; a backup (\"Back up all groups\" under Settings → Backup & restore, or one group from its group settings) writes one JSON file with the groups, including the people\'s Matrix IDs and deleted entries — and, for groups you share with an invite link, their invite key: anyone with the file can read and change those groups. Both happen only when you ask for it. Where the file goes is your choice. A CSV is always plain text; a backup is plain text too unless you set a passphrase — then it is encrypted on your device (Argon2id + AES-256-GCM) and can only be restored with that passphrase, which MoneyLedger never stores or sends anywhere. MoneyLedger has no visibility into the file afterwards. Importing or restoring reads only the file you pick.';

  @override
  String get privacyBackupTitle => 'Device backups';

  @override
  String get privacyBackupBody =>
      'MoneyLedger opts out of Android\'s automatic app backup and device-to-device transfer. Your ledger and your Matrix session (including its encryption keys) are never copied into a Google backup or onto another phone by Android. On a new device, sign in and your groups are restored from your other devices and the other people in your groups; for groups only you use, a backup file (Settings → Backup & restore) is your own offline copy.';

  @override
  String get privacyDeleteTitle => 'Deleting your data';

  @override
  String get privacyDeleteBody =>
      '• Leave or delete a group (group settings): it and all its records are removed from this device (the daily restore points keep it for about five weeks — see above). When you leave, the others in the group are told that you left.\n• Signing out keeps this account\'s ledger on the device, so it is back when you sign in again.\n• In local mode, Settings → Delete local data removes every local group from this device and ends local mode.\n• Uninstalling the app (or clearing its storage) removes everything it stored on the device.\n• Copies on other people\'s devices are theirs: they keep the group\'s history, including your expenses in it.\n• Your Matrix account can be deactivated through your homeserver.';

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
  String get notParticipating => 'You\'re not in this group';

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
      other: '$n people',
      one: '1 person',
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
  String get expensesEmptyAloneBody =>
      'It\'s just you so far. Add the people you share costs with, then the first expense.';

  @override
  String get addPeople => 'Add people';

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
  String restoreLocalIntoAccount(String account) {
    return 'This backup was made without a Matrix account. Restoring it moves its groups into $account: you are in them with that account, and this device signs your entries so they can sync.';
  }

  @override
  String restoreAccountIntoLocal(String account) {
    return 'This backup belongs to the Matrix account $account. Here you take that account\'s place in its groups; nothing is sent. Connect $account later to sync them again.';
  }

  @override
  String get restoreLocalOwnFile =>
      'Only restore a backup you made yourself: this device signs its entries as yours. Groups that include Matrix accounts are restored unsigned and won\'t sync.';

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
      'Groups you left or deleted come back on this device. If the others removed you from a group, it comes back read-only (history only) — a removal after this backup shows up at the next sync.';

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
  String backupNudgeLinkBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Anyone with the link can change or empty your $count link groups — a backup protects you.',
      one:
          'Anyone with the link can change or empty your link group — a backup protects you.',
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
      'Nobody else stores your ledger. Groups with other people are copied to their devices. For groups only you use, sign in on a second device too, or save a backup now and then (Settings → Backup & restore).';

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
    return 'Several people have the same name — the active one is used: $names';
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
      'Can\'t be checked — the device that wrote it may have signed out';

  @override
  String get recordSigVerified =>
      'Checked on arrival: it comes from this device';

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
    return '$peer has no verified device — verify one to sync with them';
  }

  @override
  String get verifiedOnlyTitle => 'Only sync with verified devices';

  @override
  String get verifiedOnlyOffBody =>
      'Off: every device of the people in your groups (and your own) gets your data.';

  @override
  String get verifiedOnlyOnBody =>
      'On: this device only sends to devices you have verified — a new login of yours too. Other devices keep syncing with each other.';

  @override
  String get verifiedOnlyConfirmTitle => 'Only sync with verified devices?';

  @override
  String get verifiedOnlyConfirmBody =>
      'This device will only send your changes to devices you have verified by comparing emojis. Unverified devices — also someone\'s new phone or a new login of yours — get nothing from here until you verify them. This only limits what this device sends: other devices keep syncing with each other.';

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
  String get recordDeviceVerifiedByYou => 'You verified this device.';

  @override
  String get recordDeviceNotVerifiedByYou =>
      'You haven\'t verified this device.';

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
  String get recordNotSyncedYet => 'Not synced yet';

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

  @override
  String get debugRunBackgroundSync => 'Run background sync now (debug)';

  @override
  String debugRunBackgroundSyncBody(int seconds) {
    return 'Queues one background round in $seconds s — close the app to test it headless.';
  }

  @override
  String get debugRunBackgroundSyncQueued => 'Background round queued.';

  @override
  String get authInProgressTitle => 'Still signing in…';

  @override
  String get authInProgressHint =>
      'The previous attempt is still waiting for the server. If it succeeds you\'re signed in automatically — otherwise try again in a moment.';

  @override
  String inviteWhoIs(Object userId) {
    return 'Who is $userId in this group?';
  }

  @override
  String get inviteAsNewParticipant => 'A new person';

  @override
  String amountPreview(Object amount) {
    return '= $amount';
  }

  @override
  String get amountMustBePositive => 'Enter an amount greater than 0';

  @override
  String get amountTooLarge => 'That amount is too large';

  @override
  String get finishingBackgroundSync => 'Finishing background sync…';

  @override
  String csvImportInvalidRow(int row, Object problem) {
    return 'Row $row: $problem';
  }

  @override
  String get welcomeSkip => 'Skip';

  @override
  String get welcomeNext => 'Next';

  @override
  String get welcomeBack => 'Back';

  @override
  String get welcomeDone => 'Done';

  @override
  String welcomePageOf(int page, int count) {
    return 'Page $page of $count';
  }

  @override
  String get welcomeIntroTitle => 'Share expenses, fairly';

  @override
  String get welcomeIntroBody =>
      'MoneyLedger keeps track of who paid what in a group — a trip, a shared flat, a dinner — and shows who owes whom, like Splitwise or Tricount. Split equally or unevenly, record payments, settle up.';

  @override
  String get welcomeOpenTitle => 'Free, open source, no server';

  @override
  String get welcomeOpenBody =>
      'MoneyLedger is free software (AGPL-3.0-or-later) — anyone can read its source code. There is no MoneyLedger server and no MoneyLedger account: your groups and expenses are stored only on your devices.';

  @override
  String get welcomeSourceLink => 'View the source code';

  @override
  String get welcomeMatrixTitle => 'What is Matrix?';

  @override
  String get welcomePrivacyServer =>
      'Homeservers only relay encrypted messages: they see which accounts exchange them and when, never the content, and keep nothing once it is delivered.';

  @override
  String get welcomePrivacyNothingElse =>
      'Nothing else: no MoneyLedger server, no tracking, no ads.';

  @override
  String get welcomeStartTitle => 'How do you want to start?';

  @override
  String get welcomeStartBody =>
      'Start right away — no account needed. Share a group with an invite link whenever you like.';

  @override
  String get welcomeSignIn => 'Sign in with Matrix';

  @override
  String get welcomeCreateAccount => 'Create a Matrix account';

  @override
  String get welcomeUseLocal => 'Start without an account';

  @override
  String get welcomeUseLocalHint =>
      'Groups you don\'t share stay on this device. You can connect a Matrix account later — your groups come along.';

  @override
  String get howItWorksTitle => 'How MoneyLedger works';

  @override
  String get localSetupStaysHere =>
      'Groups you don\'t share stay on this device only — nothing is sent anywhere.';

  @override
  String get localSetupPeople => 'Add the other people by name.';

  @override
  String get localSetupBackup =>
      'Back up regularly: if this device is lost or reset, the data is gone.';

  @override
  String get localSetupConnectLater =>
      'Share a group with an invite link — the others join without an account. You can connect a Matrix account (secure mode) later.';

  @override
  String localSetupAdoptedNotice(Object account) {
    return 'Your earlier local groups were moved into $account when you connected it — sign in with that account to see them. Local mode starts with an empty ledger.';
  }

  @override
  String get localSetupNameLabel => 'Your name';

  @override
  String get localSetupNameHelper => 'How you appear in your groups';

  @override
  String get localSetupNameRequired => 'Enter a name';

  @override
  String get localSetupStart => 'Start';

  @override
  String get localModeChip => 'No account';

  @override
  String get localModeSheetTitle => 'Without an account';

  @override
  String get localModeSheetBody =>
      'You are using MoneyLedger without an account. Groups you don\'t share with an invite link never leave this device: they aren\'t synced, and the other people are only names in your groups.';

  @override
  String get localModeBackupHint =>
      'Back up regularly (Settings → Backup & restore) — nobody else has a copy.';

  @override
  String get localModeConnectHint =>
      'Connect a Matrix account (secure mode) to sync your devices and invite people by their Matrix ID. Your groups move into that account; groups you share by link keep their link and also sync over Matrix.';

  @override
  String get localModeSettingsBody =>
      'No account — groups you don\'t share stay on this device.';

  @override
  String localProfileName(Object name) {
    return 'Your name: $name';
  }

  @override
  String get localProfileNameHint =>
      'Used for new groups — rename yourself inside a group on its People page';

  @override
  String get connectMatrixAccount => 'Connect a Matrix account';

  @override
  String get connectMatrixAccountBody =>
      'Share your groups and sync your devices — your local data moves into the account';

  @override
  String get connectSignInSubtitle =>
      'Sign in — your local groups then move into this Matrix account';

  @override
  String get deleteLocalData => 'Delete local data';

  @override
  String get deleteLocalDataBody =>
      'Removes all groups from this device and ends local mode';

  @override
  String get deleteLocalDataConfirmTitle => 'Delete all local data?';

  @override
  String deleteLocalDataConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'All $count groups with their expenses and payments are deleted from this device.',
      one:
          'The group and all its expenses and payments are deleted from this device.',
      zero: 'Local mode ends.',
    );
    return '$_temp0 There is no other copy unless you saved a backup. This can\'t be undone.';
  }

  @override
  String get deleteLocalDataConfirmAction => 'Delete everything';

  @override
  String get localModeYouSubtitle => 'You (on this device)';

  @override
  String get localModeMembersHint =>
      'No account: people are added by name. Invite them with a link from the group\'s menu, or connect a Matrix account (Settings).';

  @override
  String localAdoptedBanner(int count, Object account) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Your $count local groups now belong to $account.',
      one: 'Your local group now belongs to $account.',
    );
    return '$_temp0 You can invite people by their Matrix ID.';
  }

  @override
  String get onboardingReadyTitle => 'You\'re all set';

  @override
  String get onboardingReadyBody =>
      'A few things worth knowing now that you are signed in.';

  @override
  String get onboardingReadyLocalBody =>
      'A few things worth knowing before you start.';

  @override
  String get onboardingBackgroundTitle => 'Syncs while you are away';

  @override
  String get onboardingBackgroundBody =>
      'The devices in a group exchange changes while the app runs — on Android also about every 15 minutes in the background (Settings).';

  @override
  String get onboardingLocalOnlyTitle => 'No account needed';

  @override
  String get onboardingLocalOnlyBody =>
      'Create groups and add the other people by name. Groups you don\'t share stay on this device only.';

  @override
  String get onboardingBackupLocalBody =>
      'Nobody else has a copy of your ledger. Save a backup now and then (Settings → Backup & restore) and keep it somewhere safe.';

  @override
  String get onboardingBackupLinkBody =>
      'Everyone with the invite link has a copy of a shared group — and can change or empty it. Save a backup now and then (Settings → Backup & restore) and keep it somewhere safe.';

  @override
  String get privacyLocalTitle => 'Local mode (without an account)';

  @override
  String get privacyLocalBody =>
      'If you use MoneyLedger without a Matrix account, groups you don\'t share send nothing: for them the app contacts no server and nothing is synced (the web version is only loaded from the site that hosts it). A group you share with an invite link syncs through public Nostr relays (see “Shared groups (invite link)”). Links you tap, e.g. to the source code, open in your browser; “Fetch current rate” asks the exchange-rate service only when you tap it (see “Exchange rates”). Your name, groups, expenses and payments are stored only in a local database on this device, plus a small preferences file (whether you saw the welcome, your local profile name). Deleting local data in the settings, or uninstalling the app, removes them. If you later connect a Matrix account, the local data moves into that account and from then on the sections above apply.';

  @override
  String get categoryNone => 'No category';

  @override
  String get newCategoryEntry => 'New category…';

  @override
  String get newCategoryTitle => 'New category';

  @override
  String get editCategoryTitle => 'Edit category';

  @override
  String get categoryNameLabel => 'Name';

  @override
  String get categoryIconLabel => 'Icon';

  @override
  String categoryNameTooLong(int max) {
    return 'At most $max characters';
  }

  @override
  String get categoryNameTaken =>
      'This group already has a category with this name';

  @override
  String get manageCategories => 'Categories';

  @override
  String get customCategoriesHint =>
      'Your own categories are shared with everyone in this group. Hidden ones aren\'t offered for new expenses but still label older ones.';

  @override
  String get noCustomCategories => 'No categories of your own yet.';

  @override
  String get hideCategory => 'Hide';

  @override
  String get showCategory => 'Show again';

  @override
  String get categoryHidden => 'Hidden';

  @override
  String categoryLimitReached(int max) {
    return 'A group can have at most $max categories of its own.';
  }

  @override
  String get builtInCategories => 'Built-in';

  @override
  String get groupCategories => 'This group';

  @override
  String get restorePointsTitle => 'Restore points';

  @override
  String get restorePointsTileBody => 'Pick a day and restore it';

  @override
  String get restorePointsIntro =>
      'Once a day, when something changed, MoneyLedger keeps a copy of all your groups on this device — the last 7 days plus 4 older weeks. These copies never leave this device.';

  @override
  String get restorePointsHowItWorks =>
      'Restoring brings back groups and entries that are missing here (e.g. a deleted group). With “Exactly this state” it also undoes later changes in those groups. To undo changes inside one group, open the group → Group settings → Reset to an earlier state.';

  @override
  String get restorePointsEmpty =>
      'No restore points yet. One is made once a day when something changed.';

  @override
  String get restorePointsWebUnsupported =>
      'The browser version keeps no automatic copies. You can still reset a group to an earlier state (group → Group settings) and back up to a file.';

  @override
  String restorePointGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groups',
      one: '1 group',
    );
    return '$_temp0';
  }

  @override
  String restorePointEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0';
  }

  @override
  String get restorePointRestore => 'Restore';

  @override
  String get groupResetMenu => 'Reset to an earlier state…';

  @override
  String get groupResetTitle => 'Reset group';

  @override
  String get groupResetIntro =>
      'Pick a change to undo it and everything after it. Expenses, payments and the group settings go back to how they looked on this device before it. People stay as they are. Everyone in the group gets the result as a normal change — and you can undo a reset the same way.';

  @override
  String get groupResetLocalIntro =>
      'Pick a change to undo it and everything after it. Expenses, payments and the group settings go back to how they looked before it. People stay as they are. You can undo a reset the same way.';

  @override
  String get groupResetRetention =>
      'Changes are kept on this device for 90 days.';

  @override
  String get groupResetEmpty =>
      'Nothing to go back to yet — changes show up here as they happen.';

  @override
  String get groupResetReadOnly =>
      'You were removed from this group, so it can\'t be reset.';

  @override
  String changeAdded(int count) {
    return '$count added';
  }

  @override
  String changeEdited(int count) {
    return '$count edited';
  }

  @override
  String changeDeleted(int count) {
    return '$count deleted';
  }

  @override
  String changeOther(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes to the group or its people',
      one: '1 change to the group or its people',
    );
    return '$_temp0';
  }

  @override
  String get changeByYou => 'by you';

  @override
  String changeBy(String names) {
    return 'by $names';
  }

  @override
  String get changeUndoFromHere => 'Undo from here';

  @override
  String get changeEarliest => 'Earliest state on this device';

  @override
  String resetPreviewTitle(String time) {
    return 'Go back to before $time?';
  }

  @override
  String resetPreviewRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries come back',
      one: '1 entry comes back',
    );
    return '$_temp0';
  }

  @override
  String resetPreviewReverted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes are undone',
      one: '1 change is undone',
    );
    return '$_temp0';
  }

  @override
  String resetPreviewRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries are removed',
      one: '1 entry is removed',
    );
    return '$_temp0';
  }

  @override
  String get resetPreviewMeta =>
      'Group name, currency and categories go back too.';

  @override
  String resetPreviewSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count earlier versions can\'t be restored; those entries stay as they are.',
      one: '1 earlier version can\'t be restored; that entry stays as it is.',
    );
    return '$_temp0';
  }

  @override
  String get resetPreviewNothing =>
      'Nothing to change — the group already looks like that.';

  @override
  String get resetPreviewShared => 'Everyone in the group gets these changes.';

  @override
  String resetPreviewMore(int count) {
    return '… and $count more';
  }

  @override
  String get resetEffectRestored => 'comes back';

  @override
  String get resetEffectReverted => 'changed back';

  @override
  String get resetEffectRemoved => 'removed';

  @override
  String get resetConfirm => 'Reset';

  @override
  String resetDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Group reset ($count changes)',
      one: 'Group reset (1 change)',
    );
    return '$_temp0';
  }

  @override
  String get privacyRestorePointsTitle => 'Restore points on this device';

  @override
  String get privacyRestorePointsBody =>
      'To let you undo mistakes, MoneyLedger keeps earlier versions of your groups\' entries on this device for 90 days, and on Android once a day (when something changed) a copy of all your groups in the app\'s private storage — the last 7 days plus 4 older weeks. These versions and copies are never sent anywhere, are not part of any backup file, and are excluded from Android\'s backups like all app data. Leaving or deleting a group removes its earlier versions at once; the daily copies still contain it until they rotate out (after about five weeks), so that a group deleted by mistake can be restored. Deleting local data, or uninstalling the app, removes all of them.';

  @override
  String get expenseDateLabel => 'Date';

  @override
  String get expenseDatePickerHelp => 'When did it happen?';

  @override
  String get copy => 'Copy';

  @override
  String get copiedToClipboard => 'Copied';

  @override
  String get devicesSettingsBody =>
      'Where you\'re signed in; check devices by comparing emojis';

  @override
  String get addPeopleHint => 'It\'s just you in this group so far.';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get discardChangesTitle => 'Discard changes?';

  @override
  String get discardChangesBody =>
      'What you entered for this expense will be lost.';

  @override
  String get discard => 'Discard';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get restoreExactTitle => 'Exactly this state';

  @override
  String get restoreExactSubtitle =>
      'Also undo what changed since: edits go back, newer entries are removed, deleted ones come back. People stay as they are.';

  @override
  String get restoreExactWarning =>
      'Newer changes in these groups — also other people\'s — are overwritten for everyone in the group.';

  @override
  String get restoreExactWarningLocal =>
      'Newer changes in these groups are overwritten.';

  @override
  String get restoreExactTagMeta => 'group settings';

  @override
  String get restoreTagMergeOnly => 'only missing entries';

  @override
  String restoreExactDone(int groups, int changes) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: 'Restored $groups groups',
      one: 'Restored 1 group',
    );
    String _temp1 = intl.Intl.pluralLogic(
      changes,
      locale: localeName,
      other: '$changes changes',
      one: '1 change',
    );
    return '$_temp0 ($_temp1)';
  }

  @override
  String get createGroupPeopleLabel => 'Who\'s in?';

  @override
  String get createGroupPeopleHelper =>
      'Add the people you share costs with — Enter adds the next one. You can add more later.';

  @override
  String removePersonTooltip(String name) {
    return 'Remove $name';
  }

  @override
  String duplicatePersonHint(String name) {
    return 'There is already a $name in this group. You can still add them — a distinct name (e.g. \"$name B.\") helps tell them apart.';
  }

  @override
  String get addAndNext => 'Add & next';

  @override
  String removeMemberGetsBack(String name, String amount) {
    return '$name still gets $amount back.';
  }

  @override
  String removeMemberOwes(String name, String amount) {
    return '$name still owes $amount.';
  }

  @override
  String get removeMemberBalanceNote =>
      'Removing doesn\'t change the balance: it stays in the suggested payments until it is settled.';

  @override
  String get settleUpFirst => 'Settle up first';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsSectionSync => 'Sync';

  @override
  String get settingsSectionBackup => 'Backup & restore';

  @override
  String get settingsSectionData => 'Data';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsSectionDebug => 'Debug';

  @override
  String get settingsMatrixAccount => 'Matrix account';

  @override
  String get signOutTileBody =>
      'Your groups stay on this device for your next sign-in.';

  @override
  String get importCsvTileBody =>
      'Bring in a group from a CSV file, e.g. an export.';

  @override
  String get groupSettingsTitle => 'Group settings';

  @override
  String get groupSectionGroup => 'Group';

  @override
  String get groupSectionDevice => 'On this device';

  @override
  String get groupSectionExit => 'Leave or delete';

  @override
  String get groupNameAndCurrency => 'Name & currency';

  @override
  String groupNameCurrencyValue(String name, String currency) {
    return '$name · $currency';
  }

  @override
  String get categoriesTileBody => 'This group\'s own categories';

  @override
  String get exportCsvTileBody => 'A spreadsheet of the expenses and payments';

  @override
  String get backupGroupTileBody => 'A backup file with just this group';

  @override
  String get groupResetTileBody =>
      'Undo the changes made after a point in time';

  @override
  String get archiveTileBody =>
      'Moves it to “Archived” in your list. Only here — the others don\'t see it.';

  @override
  String get unarchiveTileBody => 'Back into your group list';

  @override
  String get leaveGroupTileBody =>
      'Removes the group from this device. The others see that you left.';

  @override
  String get deleteGroupTileBody =>
      'Removes the group and all its entries from this device.';

  @override
  String get chooseCurrencyTitle => 'Choose currency';

  @override
  String get currencySearchHint => 'Search code or name';

  @override
  String get currencySuggested => 'Suggested';

  @override
  String get currencyAll => 'All currencies';

  @override
  String get currencyNoMatch => 'No currency found';

  @override
  String expenseDeletedSnack(String description) {
    return 'Deleted \"$description\"';
  }

  @override
  String get paymentDeletedSnack => 'Payment deleted';

  @override
  String expenseAddedSnack(String description) {
    return 'Added \"$description\"';
  }

  @override
  String expenseUpdatedSnack(String description) {
    return 'Saved \"$description\"';
  }

  @override
  String get undoDone => 'Undone';

  @override
  String get undoChangedMeanwhile =>
      'Can\'t undo — this entry was changed in the meantime. Nothing was changed.';

  @override
  String get deletePayment => 'Delete payment';

  @override
  String get deleteExpenseAction => 'Delete expense';

  @override
  String get expenseDetailsTitle => 'Expense';

  @override
  String get paymentDetailsTitle => 'Payment';

  @override
  String get detailsReadOnlyHint =>
      'You can only look at this — you\'re no longer part of this group.';

  @override
  String get detailsSplitHeading => 'Split';

  @override
  String get detailsNoteHeading => 'Note';

  @override
  String get detailsDateHeading => 'Date';

  @override
  String get detailsCategoryHeading => 'Category';

  @override
  String get errorDetails => 'Details';

  @override
  String get errorDetailsTitle => 'Error details';

  @override
  String get errorInterruptedTitle => 'That didn\'t go through';

  @override
  String get errorInterruptedHint =>
      'The app was switching accounts or closing the ledger. Please try again.';

  @override
  String get errorRelayTitle =>
      'Your Matrix account can\'t be reached right now';

  @override
  String get errorRelayHint =>
      'You may be signed out, or encryption isn\'t ready yet. Try again in a moment.';

  @override
  String get errorRecordGoneTitle => 'This entry was deleted in the meantime';

  @override
  String get errorRecordGoneHint => 'Nothing was changed.';

  @override
  String get errorTooLargeTitle => 'Too much data for one message';

  @override
  String get errorTooLargeHint =>
      'This group is too large to send in one go. Please report this problem.';

  @override
  String get errorLinkOnlyTitle => 'Not possible in a link group';

  @override
  String get errorLinkOnlyHint =>
      'A group shared by link can\'t have Matrix IDs.';

  @override
  String get errorFileTitle => 'Couldn\'t read or write the file';

  @override
  String get errorFileHint =>
      'Check that the location is writable and the device has free space.';

  @override
  String get errorStorageTitle => 'Couldn\'t save on this device';

  @override
  String get errorStorageHint =>
      'The device storage reported an error. Free some space and try again.';

  @override
  String get errorTimeoutTitle => 'That took too long';

  @override
  String get errorTimeoutHint => 'Check your connection and try again.';

  @override
  String get errorNetworkTitle => 'No connection';

  @override
  String get errorNetworkHint =>
      'Check your internet connection and try again.';

  @override
  String get errorInvalidDataTitle => 'The data couldn\'t be read';

  @override
  String get errorInvalidDataHint =>
      'It seems damaged or isn\'t in the expected format.';

  @override
  String get errorUnknownTitle => 'Something went wrong';

  @override
  String get errorUnknownHint =>
      'Please try again. The details help if you report the problem.';

  @override
  String get exportFailedTitle => 'Export failed';

  @override
  String get importFailedTitle => 'Import failed';

  @override
  String get restoreFailedTitle => 'Restore failed';

  @override
  String get loadDevicesFailedTitle => 'Couldn\'t load devices';

  @override
  String get loadRestorePointsFailedTitle =>
      'Couldn\'t read the restore points';

  @override
  String get loadFailedTitle => 'Couldn\'t load the data';

  @override
  String actionFailedReason(String what, String reason) {
    return '$what — $reason';
  }

  @override
  String get settingsBackupTileBody =>
      'Backup file, automatic copies, undo changes in a group';

  @override
  String get backupDecisionTitle => 'What do you need?';

  @override
  String get backupDecisionUndo =>
      'Just deleted or changed an entry by mistake? Tap “Undo” in the message that appears right after.';

  @override
  String get backupDecisionGroup =>
      'Noticed a mistake in a group only later? Undo that group’s changes from a point in time — see “Undo changes in one group” below.';

  @override
  String get backupDecisionDevice =>
      'A whole group is gone from this device? Use a restore point.';

  @override
  String get backupDecisionDeviceWeb =>
      'A whole group is gone? Bring it back from a backup file.';

  @override
  String get backupDecisionPhone =>
      'New phone, or this one lost? Only a backup file helps — keep a recent one somewhere other than this device.';

  @override
  String get backupDecisionPhoneMatrix =>
      'Groups you share with others usually come back from them after you sign in again — groups only you are in don’t.';

  @override
  String get backupFileSection => 'Backup file';

  @override
  String get backupFileIntro =>
      'A file with all your groups that you keep somewhere else — on a computer or in your cloud. You can restore it on any device.';

  @override
  String get backupFileGroupHint =>
      'Just one group: open the group → Group settings → Back up this group.';

  @override
  String get backupRestorePointsIntro =>
      'Once a day, MoneyLedger automatically keeps a copy of all your groups on this device. It brings back groups or entries that went missing here — but it is gone together with the device.';

  @override
  String get backupShowRestorePoints => 'Show restore points';

  @override
  String get backupRestorePointsWeb =>
      'Not available in the browser: it keeps no automatic copies. Save a backup file regularly instead.';

  @override
  String get backupUndoSection => 'Undo changes in one group';

  @override
  String get backupUndoIntro =>
      'Lists a group’s changes on this device and puts the group back to how it was before one of them — e.g. after a wrong import. That is a normal change: people you share the group with get it too.';

  @override
  String get backupUndoPickGroup => 'Choose a group …';

  @override
  String get backupUndoPickGroupBody =>
      'Also in each group’s settings: Reset to an earlier state';

  @override
  String get backupUndoNoGroups => 'No groups yet';

  @override
  String get backupUndoPickTitle => 'Which group?';

  @override
  String get shareBalances => 'Share who pays whom';

  @override
  String shareBalanceTitle(String group) {
    return '$group – who pays whom';
  }

  @override
  String get shareAllSettled => 'All settled up.';

  @override
  String shareCurrencyHeader(String currency) {
    return 'In $currency:';
  }

  @override
  String shareDebtLine(String from, String to, String amount) {
    return '$from → $to: $amount';
  }

  @override
  String get shareFooter => 'Made with MoneyLedger';

  @override
  String get shareCopiedFallback =>
      'Sharing isn’t available here – the text was copied to the clipboard.';

  @override
  String get statsSection => 'Overview';

  @override
  String get statsTotalSpent => 'Total spent';

  @override
  String statsExpenseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count expenses',
      one: '1 expense',
    );
    return '$_temp0';
  }

  @override
  String get statsPerPerson => 'Paid and share per person';

  @override
  String statsPaid(String amount) {
    return 'paid $amount';
  }

  @override
  String statsShare(String amount) {
    return 'share $amount';
  }

  @override
  String get statsByCategory => 'By category';

  @override
  String statsMoreCategories(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more categories',
      one: '1 more category',
    );
    return '$_temp0';
  }

  @override
  String get verifiedOnlyLearnMore => 'Learn more';

  @override
  String get verifiedOnlyMoreBody =>
      'Verify your own devices on the Devices page, other people\'s on the People page of a group.\n\nUnverified devices fall behind: a new login of your own can\'t restore your groups from this device until you verify it there.\n\nOther people\'s devices, and your other devices, keep syncing with each other unless they turn this on too.\n\nWhat you receive is still accepted; an entry\'s details show whether you verified the device that wrote it. Applies to this device and account only.';

  @override
  String get settingsSectionAdvanced => 'Advanced (Matrix)';

  @override
  String get webLimitsTitle => 'MoneyLedger in the browser';

  @override
  String get webLimitsBody =>
      'It only syncs while this tab is open — there\'s no background sync. There are no automatic restore points either, and your data is stored in this browser only (clearing its site data deletes it). Make a backup now and then.';

  @override
  String get webLimitsBodyLocal =>
      'There are no automatic restore points in the browser, and your data is stored in this browser only (clearing its site data deletes it). Make a backup now and then.';

  @override
  String get webLimitsBackup => 'Back up';

  @override
  String get webLimitsDismiss => 'Got it';

  @override
  String get duplicateExpense => 'Duplicate';

  @override
  String duplicatePersonRenameHint(String name) {
    return 'There is already a $name in this group. A distinct name (e.g. \"$name B.\") helps tell them apart.';
  }

  @override
  String deleteExpenseBodyLocal(String description) {
    return '\"$description\" will be deleted from this device.';
  }

  @override
  String deleteSettlementBodyLocal(String from, String to, String amount) {
    return '\"$from paid $to $amount\" will be deleted from this device and the balance restored.';
  }

  @override
  String get errorTryAgain => 'Try again';

  @override
  String get splitByItemsAction => 'Split by items…';

  @override
  String get itemsTitle => 'Split by items';

  @override
  String itemsReceiptTotal(String amount) {
    return 'Total: $amount';
  }

  @override
  String get itemsNoTotal => 'No amount yet';

  @override
  String get itemsNotStoredHint =>
      'Each item is split equally among its people. Only the amounts per person are saved, not the items.';

  @override
  String itemLabel(int n) {
    return 'Item $n';
  }

  @override
  String get itemAdd => 'Add item';

  @override
  String get itemRemove => 'Remove item';

  @override
  String get itemEveryone => 'Everyone';

  @override
  String itemEach(String amount) {
    return '$amount each';
  }

  @override
  String get itemsEnterOne => 'Enter at least one item amount';

  @override
  String itemsRest(String amount) {
    return 'Rest (tax, tip, not itemized): $amount';
  }

  @override
  String get itemsRestProportional => 'Proportionally';

  @override
  String get itemsRestEqually => 'Equally';

  @override
  String get itemsRestProportionalHint =>
      'The rest is shared in proportion to what each person had.';

  @override
  String get itemsRestEqualHint =>
      'The rest is shared equally among everyone with an item.';

  @override
  String get itemsResult => 'Per person';

  @override
  String get itemsApply => 'Use this split';

  @override
  String get receiptPhotoLabel => 'Receipt photo';

  @override
  String get receiptAdd => 'Add receipt photo';

  @override
  String get receiptTakePhoto => 'Take photo';

  @override
  String get receiptChooseFromGallery => 'Choose from gallery';

  @override
  String get receiptLocalOnlyHint =>
      'Only on this device — not shared with the group, not in backups.';

  @override
  String get receiptView => 'View receipt photo';

  @override
  String get receiptReplace => 'Replace';

  @override
  String get receiptRemove => 'Remove';

  @override
  String get receiptUnreadable => 'This photo can\'t be shown.';

  @override
  String get receiptPickFailed => 'Couldn\'t get the photo';

  @override
  String get receiptSaveFailed =>
      'The expense was saved, but its receipt photo couldn\'t be stored';

  @override
  String get expenseHasReceipt => 'Has a receipt photo';

  @override
  String get privacyReceiptsTitle => 'Receipt photos (Android)';

  @override
  String get privacyReceiptsBody =>
      'On Android you can attach a photo of the receipt to an expense, taken with your camera app or picked from your photos. MoneyLedger stores a smaller copy only in the app\'s private storage on this device. It is never sent anywhere — not to the others in the group, not to any homeserver — is not part of any backup file, restore point or CSV, and is excluded from Android\'s backups like all app data. It is deleted with its expense (the next time the app starts), when you leave or delete the group, and when you delete local data or uninstall the app; signing out keeps it. The camera and photo picker are Android\'s own: MoneyLedger asks for no camera or storage permission and only receives the one photo you choose.';

  @override
  String get receiptSavedSnack => 'Receipt photo saved';

  @override
  String get receiptRemovedSnack => 'Receipt photo removed';

  @override
  String get inviteByLink => 'Invite with a link';

  @override
  String get inviteByLinkTileBody =>
      'Share a link or QR code — no account needed';

  @override
  String get inviteByLinkTileBodyOpen => 'Show the invite link and QR code';

  @override
  String get linkInviteSheetBody =>
      'Send this link to the people in the group. They open it in MoneyLedger and pick who they are — no account needed.';

  @override
  String get linkInviteQrLabel => 'QR code of the invite link';

  @override
  String get linkInviteQrHint =>
      'Or let them scan this code with their phone\'s camera.';

  @override
  String get linkInviteShare => 'Share link';

  @override
  String get linkInviteCopied => 'Invite link copied';

  @override
  String get linkInviteWarning =>
      'Anyone with this link can see and change this group. Only share it with the people in it.';

  @override
  String get linkInviteRecoveryHint =>
      'If something gets changed or deleted by mistake, you can reset the group to an earlier state in the group settings.';

  @override
  String get linkInviteMatrixGroup =>
      'This group is shared with Matrix accounts, so it can\'t get an invite link yet. Invite people by Matrix ID on the People page.';

  @override
  String get linkDisclosureTitle => 'Sharing with a link';

  @override
  String linkDisclosureRelays(String relays) {
    return 'Shared groups sync through public Nostr relays: $relays. They are independent services with their own terms (linked under Settings → Relays).';
  }

  @override
  String get linkDisclosureEncrypted =>
      'They store your group encrypted — only people with the link can read it.';

  @override
  String get linkDisclosureMetadata =>
      'The relays see your IP address and when you sync, and may keep data longer than the 30 days we ask for.';

  @override
  String get linkDisclosureAnyone =>
      'Anyone with the link can see and change the group.';

  @override
  String get linkDisclosureMatrix =>
      'Want accounts and verified devices? Use Matrix (secure mode).';

  @override
  String get linkDisclosureContinue => 'Continue';

  @override
  String get createGroupShareByLink => 'Share with an invite link';

  @override
  String get createGroupShareByLinkBody =>
      'Others join without an account. Anyone with the link can see and change the group. Off: you invite Matrix accounts (secure).';

  @override
  String get linkMembersHint =>
      'Shared with a link: people are added by name. Whoever opens the invite link picks who they are.';

  @override
  String get privacyLinkTitle => 'Shared groups (invite link)';

  @override
  String get privacyLinkBody =>
      'A group you share with an invite link syncs through public Nostr relays — by default nos.lol and nostr.mom, which have one operator. They are independent services with their own terms. You can change the relays under Settings → Relays: adding one first asks it for its information page (NIP-11), then your shared groups sync through it too. Every device in the group publishes its copy of the group there, encrypted (AES-256-GCM) with a key that only the link contains; the key never goes to a relay or to any server of ours. The relays can\'t read names, amounts or notes, but they see your device\'s IP address, when it syncs, roughly how large the group is and how many devices take part, and that the data comes from MoneyLedger. We ask them to delete each copy after 30 days (renewed while the group is in use), but relays may keep or archive data longer — and anyone who gets the link, now or later, can read and change the group, also from archived copies. When you delete a shared group from this device (or delete local data), the app first asks the relays to delete your copy; the others in the group keep theirs. Resetting the invite link (or switching to a new link someone sent you) asks the relays to delete your copy under the old link and publishes the group under a new key; people who only have the old link no longer get your changes, but keep what they already saw. A group only on this device never contacts a relay: a group starts syncing only when you invite with a link, create it with “Share with an invite link” or join it with a link someone sent you — or, in a group shared with Matrix accounts, when one of its members invites with a link: then your devices share that group through the relays in the same way, and changes made through the link are marked “not verified”. In such a group — also once someone who joined by link connects a Matrix account — everyone with the link sees the Matrix IDs of the people in it who use Matrix. Making such a group secure (once everyone in it has a Matrix account) asks the relays to delete the copies, and the link stops working. Opening an invite link contacts nothing until you tap “Join”; the relays are then asked for that group.';

  @override
  String linkInviteShareText(String group, String link) {
    return 'Join “$group” in MoneyLedger: $link';
  }

  @override
  String get joinLinkTitle => 'Join a group';

  @override
  String get joinLinkEntry => 'Join with an invite link';

  @override
  String get joinLinkPasteHint => 'Paste the invite link someone sent you.';

  @override
  String get joinLinkPasteLabel => 'Invite link';

  @override
  String get joinLinkContinue => 'Continue';

  @override
  String get joinLinkInvalidTitle => 'This invite link doesn\'t work';

  @override
  String get joinLinkInvalidBody =>
      'Check that the whole link was copied, or ask for it again.';

  @override
  String get joinLinkUpdateApp =>
      'This invite link needs a newer version of MoneyLedger. Please update the app.';

  @override
  String get joinLinkInvited => 'You\'ve been invited to a group.';

  @override
  String get joinLinkIntroBody =>
      'MoneyLedger looks the group up on the relays and then asks who you are in it.';

  @override
  String get joinLinkNoAccountHint =>
      'No account needed: MoneyLedger starts without an account on this device.';

  @override
  String get joinLinkSearching => 'Looking for the group…';

  @override
  String get joinLinkNotFoundTitle => 'Couldn\'t find this group yet';

  @override
  String get joinLinkNotFoundBody =>
      'The person who invited you needs to open MoneyLedger once so the group is shared. Try again in a moment.';

  @override
  String get joinLinkRetry => 'Try again';

  @override
  String get joinLinkBlockedTitle => 'Can\'t join with this link';

  @override
  String get joinLinkNotALinkGroup =>
      'This group is already on this device and isn\'t shared with a link here, so this link can\'t add it.';

  @override
  String get joinLinkOtherLink =>
      'This group is already on this device with a different invite link.';

  @override
  String get joinLinkUsedElsewhere => 'Already picked on another phone';

  @override
  String get joinLinkPersonGone =>
      'This person is no longer in the group. Please pick again.';

  @override
  String joinLinkInvitedTo(String group) {
    return 'You\'ve been invited to “$group”.';
  }

  @override
  String joinLinkPickTitle(String group) {
    return 'Who are you in “$group”?';
  }

  @override
  String get syncSheetTitle => 'Sync';

  @override
  String get syncSheetAllSynced => 'Everyone has your latest changes.';

  @override
  String get syncSheetPending => 'Not everyone has your latest changes yet.';

  @override
  String get syncSheetNoPeers =>
      'Nobody else in this group has a Matrix account — there is nothing to sync.';

  @override
  String get syncSheetLocalPeople =>
      'People without a Matrix account don\'t sync — they are entries in the ledger only.';

  @override
  String get peerUpToDate => 'Has everything';

  @override
  String peerUpToDateAt(String ago) {
    return 'Has everything · checked $ago';
  }

  @override
  String peerWaitingSince(String ago) {
    return 'Waiting — last in sync $ago';
  }

  @override
  String get peerWaitingNever => 'Waiting — not in sync yet';

  @override
  String get peerNoDevice => 'No signed-in device — syncs once they sign in';

  @override
  String get peerUnverified => 'No verified device — verify one to sync';

  @override
  String get peerYourDevices => 'Your other devices';

  @override
  String get peerUnknown => 'Unknown person';

  @override
  String peerPublishedAt(String ago) {
    return 'Last update $ago';
  }

  @override
  String get peerDeletedGroup => 'Deleted the group';

  @override
  String peerDeletedGroupAt(String ago) {
    return 'Deleted the group $ago';
  }

  @override
  String peerDevices(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n devices',
      one: '1 device',
    );
    return '$_temp0';
  }

  @override
  String get syncSheetLinkNoPeers =>
      'Nobody else has opened the invite link yet.';

  @override
  String get syncSheetLinkHint =>
      'People who haven\'t opened the invite link yet don\'t appear here. “Has everything” means their device published the same state as yours.';

  @override
  String linkSyncSynced(String ago) {
    return 'Your changes are on the relays ($ago).';
  }

  @override
  String get linkSyncSyncedNoTime => 'Your changes are on the relays.';

  @override
  String get linkSyncPending => 'Sending your changes to the relays…';

  @override
  String get linkSyncNotDelivered =>
      'Couldn\'t reach the relays — trying again.';

  @override
  String get linkSyncRelaysReject =>
      'The relays refuse our updates. Add another relay under Settings → Relays.';

  @override
  String get linkSyncTooLarge =>
      'This group is too big for sharing with a link.';

  @override
  String get linkSyncNoParticipant => 'Choose who you are in this group first.';

  @override
  String get linkSyncMergeFailed =>
      'An update couldn\'t be stored — trying again.';

  @override
  String get linkCloudSynced => 'Synced through the relays';

  @override
  String get linkCloudOffline => 'Offline — no relay reachable';

  @override
  String get linkSyncOffline =>
      'No relay can be reached right now — are you offline? What changed since the last sync is sent as soon as the connection is back.';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncNowSent =>
      'Asked everyone for their state — they answer while their app runs.';

  @override
  String get syncNowChecked => 'Checked the relays.';

  @override
  String get syncNowUnreachable => 'Couldn\'t reach the relays.';

  @override
  String get relaysTitle => 'Relays';

  @override
  String relaysTileBody(String relays) {
    return 'Invite-link groups sync through: $relays';
  }

  @override
  String get relaysTileProblem => 'A relay refuses our updates';

  @override
  String get relaysIntro =>
      'Groups shared with an invite link sync through these public Nostr relays. They store each group encrypted and see your IP address and when you sync. They are independent services with their own terms.';

  @override
  String get relaysOneOperator =>
      'nos.lol and nostr.mom have the same operator. If they stop accepting our updates, groups only keep syncing through a relay you add — for example your own.';

  @override
  String get relaysCommon =>
      'The invite link doesn\'t name relays: everyone in a group needs at least one relay in common. This list only applies to this device.';

  @override
  String relayStatusRejects(String message) {
    return 'Refuses our updates: $message';
  }

  @override
  String relayStatusRateLimited(int n) {
    return 'Asked us to slow down — next try in $n min';
  }

  @override
  String get relayStatusNeedsAccount => 'Needs an account — can\'t be used';

  @override
  String get relayStatusNoExpiration =>
      'Doesn\'t support expiring data (NIP-40)';

  @override
  String relayStatusLastRefused(String ago, String message) {
    return 'Refused our last update ($ago): $message';
  }

  @override
  String relayStatusOk(String ago) {
    return 'Accepted our last update $ago';
  }

  @override
  String get relayStatusUnused => 'Not used yet';

  @override
  String get relayTerms => 'Terms';

  @override
  String relayTermsOf(String relay) {
    return 'Terms of $relay';
  }

  @override
  String relayRemove(String relay) {
    return 'Remove $relay';
  }

  @override
  String relayRemoveConfirmTitle(String relay) {
    return 'Remove $relay?';
  }

  @override
  String get relayRemoveConfirmBody =>
      'This device stops syncing shared groups through it.';

  @override
  String get relayRemoveConfirm => 'Remove';

  @override
  String get relayRemoved => 'Relay removed.';

  @override
  String get relayAdd => 'Add relay…';

  @override
  String get relayAddTitle => 'Add a relay';

  @override
  String get relayAddLabel => 'Relay address';

  @override
  String get relayAddConfirm => 'Add';

  @override
  String get relayAddInvalid =>
      'That isn\'t a relay address (e.g. wss://relay.example.org).';

  @override
  String get relayAddNotSecure =>
      'Only encrypted connections (wss://) are supported.';

  @override
  String get relayAddDuplicate => 'This relay is already in the list.';

  @override
  String get relayAddChecking => 'Checking the relay…';

  @override
  String get relayAddNeedsAccount =>
      'This relay needs an account — it can\'t be used.';

  @override
  String get relayAddNoExpiration =>
      'This relay doesn\'t support expiring data (NIP-40) — it would keep your groups indefinitely.';

  @override
  String get relayAddUncheckedTitle => 'Couldn\'t check this relay';

  @override
  String get relayAddUncheckedBody =>
      'It didn\'t answer the check (NIP-11) — maybe it\'s offline or the address is wrong. Add it anyway?';

  @override
  String get relayAddAnyway => 'Add anyway';

  @override
  String get relayAdded =>
      'Relay added — your shared groups are sent to it now.';

  @override
  String get relaysRestoreDefaults => 'Use the default relays';

  @override
  String get relaysDefaultsRestored => 'Default relays restored.';

  @override
  String get backgroundSyncLocalBody =>
      'Also check the relays for your shared groups about every 15 minutes while the app is closed.';

  @override
  String linkDisclosureRelaysOneOperator(String relays) {
    return 'Shared groups sync through two public Nostr relays, $relays (one operator). They are independent services with their own terms (linked under Settings → Relays).';
  }

  @override
  String get linkDisclosureOwnRelay =>
      'You can add your own relay under Settings → Relays.';

  @override
  String get deleteLinkGroupNote =>
      'This group is shared with an invite link: the others keep their copies. Your copy is removed from the relays, and you can join again with the link.';

  @override
  String get linkUnpublishing => 'Removing your copy from the relays…';

  @override
  String deleteLocalDataLinkNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count of them are shared with an invite link: the others keep their copies, yours are removed from the relays.',
      one:
          'One of them is shared with an invite link: the others keep their copies, yours is removed from the relays.',
    );
    return '$_temp0';
  }

  @override
  String backupLinkKeysWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'The file contains the invite keys of $count shared groups: anyone with the file can read and change them.',
      one:
          'The file contains the invite key of one shared group: anyone with the file can read and change that group.',
    );
    return '$_temp0';
  }

  @override
  String restoreLinkKeysWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This file contains the invite keys of $count shared groups: anyone with the file can read and change them. After the restore, open each of them and choose who you are — then they sync again.',
      one:
          'This file contains the invite key of one shared group: anyone with the file can read and change it. After the restore, open the group and choose who you are — then it syncs again.',
    );
    return '$_temp0';
  }

  @override
  String get backupFileLinkNote =>
      'The file also contains the invite keys of your shared groups — with it, anyone can read and change them. Set a passphrase when you save it.';

  @override
  String get linkChooseMeBanner =>
      'Which person are you in this group? It syncs again once you choose.';

  @override
  String get linkResetMenu => 'Reset invite link';

  @override
  String get linkResetTileBody => 'New link — the old one stops working';

  @override
  String get linkResetSheetHint =>
      'For example after removing someone: anyone with this link can still open the group.';

  @override
  String get linkResetTitle => 'Reset invite link?';

  @override
  String get linkResetBody =>
      'This makes a new invite link. Your changes then only go to people who use the new link — so send it to everyone who is still in the group.\n\nPeople who only have the old link (for example someone you removed) no longer see your changes; they keep what they have already seen. The old link stops working completely once everyone has switched to the new one.';

  @override
  String get linkResetConfirm => 'Reset link';

  @override
  String get linkResetting => 'Resetting the invite link…';

  @override
  String get linkResetFailed => 'Couldn\'t reset the invite link';

  @override
  String get linkResetDoneHint =>
      'This is the new link. Send it to everyone still in the group — until they open it, you don\'t see each other\'s changes.';

  @override
  String removeMemberLinkNote(Object name) {
    return '$name can still open the group with the invite link. To lock them out, reset the invite link afterwards (group settings) and send the new one to the others.';
  }

  @override
  String joinLinkSwitchTitle(Object group) {
    return 'Switch “$group” to this link?';
  }

  @override
  String get joinLinkSwitchTitleNoName => 'Switch to this link?';

  @override
  String get joinLinkSwitchBody =>
      'This group is already on this device with a different invite link. If someone in the group reset the link and sent you this one, switch to it: you stay the same person, and your phone then syncs with everyone who uses the new link.';

  @override
  String get joinLinkSwitchCaution =>
      'Only switch if you got this link from someone in the group. Your copy is removed from the old link.';

  @override
  String get joinLinkSwitchConfirm => 'Use this link';

  @override
  String get joinLinkSwitchKeep => 'Keep the old link';

  @override
  String get recordViaLink => 'Via link · not verified';

  @override
  String recordViaLinkBy(String name) {
    return 'Changed by $name via link · not verified';
  }

  @override
  String get errorSignatureRequiredTitle =>
      'Only possible with a Matrix account';

  @override
  String get errorSignatureRequiredHint =>
      'In this group, the name, currency, categories and people with a Matrix account can only be changed by someone signed in with Matrix.';

  @override
  String get linkMixedTitle => 'Also share this group by link?';

  @override
  String get linkMixedBody =>
      'Anyone with the link can then see and change this group without an account — and sees the Matrix IDs of the people in it. Their changes are marked “not verified”, and only people signed in with Matrix can change the name, currency or categories.\n\nYour devices and those of the others signed in with Matrix will also share the group through the relays, encrypted with the link\'s key.\n\nOnce everyone has a Matrix account, you can make the group secure again: the link then stops working.';

  @override
  String get linkMixedConfirm => 'Share by link';

  @override
  String get linkMixedOpening => 'Creating the invite link…';

  @override
  String get lockGroupTile => 'Make group secure';

  @override
  String get lockGroupTileBody =>
      'Only Matrix accounts from now on — the invite link stops working';

  @override
  String get lockBlockedTitle => 'Not everyone has a Matrix account yet';

  @override
  String lockBlockedBody(String names) {
    return 'Before the group can be made secure, these people need to connect a Matrix account in MoneyLedger (Settings → Connect a Matrix account) — or be removed from the group: $names';
  }

  @override
  String get lockConfirmTitle => 'Make this group secure?';

  @override
  String get lockConfirmBody =>
      'The invite link stops working: the relays are asked to delete the group\'s copies, and changes made through the link are no longer accepted. Everyone keeps syncing with their Matrix account.\n\nYou can share the group by link again later — with a new link.';

  @override
  String get lockConfirm => 'Make secure';

  @override
  String get lockRunning => 'Making the group secure…';

  @override
  String get lockDone => 'The group is secure now — Matrix accounts only.';

  @override
  String get lockFailed => 'Couldn\'t make the group secure';

  @override
  String get secureOnlyBanner =>
      'This group is now secure-only — sign in with Matrix to keep using it.';

  @override
  String get onboardingInviteLinkTitle => 'Invite with a link';

  @override
  String get onboardingInviteLinkBody =>
      'In a group, tap ⋮ → Invite with a link: the others open it and pick their name — no account needed. Anyone with the link can see and change the group.';

  @override
  String get welcomeLinkTitle => 'Share a group with a link';

  @override
  String get welcomeLinkBody =>
      'Send the others an invite link — by messenger, e-mail or as a QR code. They open it, pick their name, and everyone sees the same expenses. Nobody needs an account.';

  @override
  String get welcomeLinkEncrypted =>
      'The group syncs encrypted through public Nostr relays — only people with the link can read it.';

  @override
  String get welcomeLinkRelays =>
      'The relays see your IP address and when you sync, never the content.';

  @override
  String get welcomeLinkAnyone =>
      'Anyone with the link can see and change the group — share it only with the people in it.';

  @override
  String get welcomeSecureTitle => 'Want more security? Matrix';

  @override
  String get welcomeSecureBody =>
      'Matrix is an open, decentralized messaging network. Like with e-mail, you choose a provider (a \"homeserver\", e.g. matrix.org) and create a free account there. Signed in, MoneyLedger syncs your groups end-to-end encrypted with the people you added — the secure mode.';

  @override
  String get welcomeSecureMembers =>
      'Only the people you added get a group — every change is signed by the device that made it.';

  @override
  String get welcomeSecureHeading => 'Secure mode';

  @override
  String get welcomeSecureHint =>
      'With a free Matrix account: only people you added, signed changes, your groups on every device.';

  @override
  String get whyMatrixTitle => 'Why Matrix?';

  @override
  String get whyMatrixEasyTitle => 'Links are easy';

  @override
  String get whyMatrixEasyBody =>
      'A link is the quickest way to share a group: send it, the others pick their name, done. No account, no sign-up — that\'s why it\'s the default, and for a trip or a dinner it\'s often all you need.';

  @override
  String get whyMatrixCompareTitle => 'There\'s another mode';

  @override
  String get whyMatrixCompareBody =>
      'Matrix is free too, and it works even better — you just sign in. What changes:';

  @override
  String get whyMatrixWhoTitle => 'Who can see and change a group';

  @override
  String get whyMatrixWhoLink =>
      'anyone who has the link, also when it\'s forwarded.';

  @override
  String get whyMatrixWhoMatrix =>
      'only the people you added; every change is signed by the device that made it.';

  @override
  String get whyMatrixRemoveTitle => 'Removing someone';

  @override
  String get whyMatrixRemoveLink =>
      'they keep access until you reset the link and send the new one to everyone else.';

  @override
  String get whyMatrixRemoveMatrix =>
      'it sticks — their changes are ignored from then on.';

  @override
  String get whyMatrixPhoneTitle => 'New or lost phone';

  @override
  String get whyMatrixPhoneLink => 'you need the link (or a backup) again.';

  @override
  String get whyMatrixPhoneMatrix =>
      'sign in, and your groups come back from your other devices or the others in the group.';

  @override
  String get whyMatrixServersTitle => 'Who sees what';

  @override
  String get whyMatrixServersLink =>
      'public relays run by volunteers see your IP address, when you sync and roughly how big the group is.';

  @override
  String get whyMatrixServersMatrix =>
      'only the homeservers of the people in the group (each picks their own) see who exchanges messages with whom — never the content.';

  @override
  String get whyMatrixReadyTitle => 'Ready when you are';

  @override
  String get whyMatrixReadyConnectBody =>
      'Create a free account, e.g. at matrix.org, and connect it. Your groups come along; groups you share by link keep their link and also sync over Matrix.';

  @override
  String get whyMatrixReadySignInBody =>
      'Create a free account, e.g. at matrix.org, and sign in — or start without an account and connect one any time later.';

  @override
  String get whyMatrixReadySignedInBody =>
      'You\'re already signed in with Matrix. Groups you create are Matrix groups. In a group that is also shared by link, Make group secure (group settings) closes the link once everyone in it is on Matrix.';

  @override
  String get whyMatrixReadyLaterBody =>
      'Matrix is free. You can connect an account any time later in the settings — your groups come along.';

  @override
  String get whyMatrixNotNow => 'Not now';

  @override
  String get whyMatrixHintTitle => 'There\'s also a secure mode';

  @override
  String get whyMatrixHintBody =>
      'Your link group is in full use. With a free Matrix account, only the people you added can see a group, and every change is signed.';

  @override
  String get whyMatrixHintBodyMatrix =>
      'Your link group is in full use. Anyone with its link can see and change it. Groups you create with your Matrix account are seen only by the people you added, and every change is signed.';

  @override
  String get whyMatrixHintMore => 'Tell me more';

  @override
  String whyMatrixWithLink(String text) {
    return 'Link: $text';
  }

  @override
  String whyMatrixWithMatrix(String text) {
    return 'Matrix: $text';
  }

  @override
  String get exchangeRatesTitle => 'Exchange rates';

  @override
  String get exchangeRatesTileNone =>
      'Not set — currencies are settled separately';

  @override
  String exchangeRatesTileRates(int count, String base) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rates in $base',
      one: '1 rate in $base',
    );
    return '$_temp0';
  }

  @override
  String exchangeRatesTileSettled(String rates, String base) {
    return '$rates · settle up in $base';
  }

  @override
  String exchangeRatesIntro(String base) {
    return 'Fixed rates you enter yourself. They belong to the group: everyone in it sees and uses the same rates. Rates are given in $base.';
  }

  @override
  String settleInBase(String base) {
    return 'Settle up in $base';
  }

  @override
  String get settleInBaseBody =>
      'Balances and suggested payments convert the other currencies at these rates. A currency without a rate stays separate.';

  @override
  String rateRow(String from, String rate, String base) {
    return '1 $from = $rate $base';
  }

  @override
  String get addRate => 'Add rate';

  @override
  String get removeRate => 'Remove rate';

  @override
  String get noRatesYet => 'No rates yet.';

  @override
  String ratesMissingFor(String currencies) {
    return 'Used in this group without a rate: $currencies';
  }

  @override
  String rateDialogTitle(String from, String base) {
    return '1 $from in $base';
  }

  @override
  String rateFieldLabel(String base) {
    return 'Rate in $base';
  }

  @override
  String get rateInvalid =>
      'Enter a number greater than 0 (at most 10 decimals).';

  @override
  String get fetchRate => 'Fetch current rate';

  @override
  String fetchRateSource(String host) {
    return 'Asks Frankfurter ($host, reference rates of central banks) — only when you tap. It sees your IP address and the two currencies, nothing about the group.';
  }

  @override
  String fetchedRateFrom(String date) {
    return 'Reference rate of $date (Frankfurter) — check it before saving.';
  }

  @override
  String get fetchRateUnavailable =>
      'No rate available for this pair — enter it yourself.';

  @override
  String get fetchRateFailedTitle => 'Couldn\'t fetch the rate';

  @override
  String settledInBaseNote(String base) {
    return 'Settled in $base: other currencies are converted at the group\'s fixed rates.';
  }

  @override
  String get setExchangeRates => 'Set exchange rates';

  @override
  String get privacyRatesTitle => 'Exchange rates';

  @override
  String get privacyRatesBody =>
      'A group can have fixed exchange rates that you enter yourself; they are part of the group and sync to everyone in it like its name. Only when you tap “Fetch current rate”, the app asks Frankfurter (api.frankfurter.dev — a free, open-source service publishing reference rates of the European Central Bank and other central banks) for the rate between the two currencies. The request goes directly from your device and needs no account or key; the service (and its hosting provider) sees your device\'s IP address, the two currency codes and the time — nothing about your groups, the people in them or any amounts. It is never contacted automatically, and the fetched rate is only filled in for you to check before you save it.';

  @override
  String get settingsSectionPayment => 'Payment details';

  @override
  String get paymentDetailsTileTitle => 'Bank account & PayPal.me';

  @override
  String get paymentDetailsTileNone =>
      'Optional — your groups see them when they pay you back';

  @override
  String paymentDetailsTileIban(String last4) {
    return 'IBAN ending $last4';
  }

  @override
  String get paymentDetailsIntro =>
      'Optional. Everyone in the groups you\'re in gets them, so they can pay you back: the balance page shows a GiroCode for a banking app (euro only) or your PayPal.me link with the amount — on your phone for them to scan, and on theirs when they owe you.';

  @override
  String get paymentBankSection => 'Bank account (SEPA)';

  @override
  String get paymentNameLabel => 'Account holder';

  @override
  String get paymentNameRequired =>
      'Enter the account holder — the bank needs it.';

  @override
  String get paymentIbanLabel => 'IBAN';

  @override
  String get paymentIbanInvalid =>
      'This isn\'t a valid IBAN — check it for typos.';

  @override
  String get paymentBicLabel => 'BIC (optional)';

  @override
  String get paymentBicHelper => 'Only needed for some banks outside the EU.';

  @override
  String get paymentBicInvalid => 'A BIC has 8 or 11 letters and digits.';

  @override
  String get paymentPaypalSection => 'PayPal';

  @override
  String get paymentPaypalLabel => 'PayPal.me name';

  @override
  String get paymentPaypalHelper =>
      'Your name from the link paypal.me/name — you can also paste the whole link.';

  @override
  String get paymentPaypalInvalid => 'Only letters and digits, up to 20.';

  @override
  String get paymentDetailsClear => 'Clear all fields';

  @override
  String get paymentDetailsSaved => 'Payment details saved';

  @override
  String get paymentDetailsCleared => 'Payment details removed';

  @override
  String get paymentShowDetails => 'Show my payment details';

  @override
  String paymentRequestTitle(String name, String amount) {
    return '$name pays you $amount';
  }

  @override
  String get paymentMethodBank => 'Bank transfer';

  @override
  String get paymentMethodPaypal => 'PayPal';

  @override
  String paymentGiroCodeSemantics(String amount) {
    return 'GiroCode QR code for a bank transfer of $amount';
  }

  @override
  String get paymentGiroCodeHint =>
      'Scan with a banking app (GiroCode) — name, IBAN and amount are filled in.';

  @override
  String get paymentGiroCodeEuroOnly =>
      'A GiroCode works only for euro — the bank account:';

  @override
  String get paymentCopyIban => 'Copy IBAN';

  @override
  String paymentPaypalQrSemantics(String amount) {
    return 'QR code of the PayPal.me link for $amount';
  }

  @override
  String get paymentPaypalQrHint =>
      'Scan with the phone camera to open PayPal with the amount.';

  @override
  String get paymentShareLink => 'Share link';

  @override
  String get paymentRequestLocalNote =>
      'Your groups see these details too — change them under Settings → Payment details.';

  @override
  String get paymentDetailsLinkWarning =>
      'Groups you share with an invite link get them too: anyone with a group\'s link can read them. If you change or remove them later, earlier copies stay in the others\' history, backups and restore points.';

  @override
  String paymentPayTitle(String name, String amount) {
    return 'You pay $name $amount';
  }

  @override
  String paymentPaysTitle(String payer, String payee, String amount) {
    return '$payer pays $payee $amount';
  }

  @override
  String get paymentOpenPaypal => 'Open PayPal';

  @override
  String paymentSharedByNote(String name) {
    return '$name shared these details with the group.';
  }

  @override
  String paymentShowDetailsOf(String name) {
    return 'Payment details of $name';
  }

  @override
  String get privacyPaymentTitle => 'Payment details';

  @override
  String get privacyPaymentBody =>
      'You can enter your own bank account (account holder, IBAN, BIC) and PayPal.me name under Settings → Payment details. MoneyLedger stores them on this device, for the account you use (or local mode — they move along when you connect a Matrix account), and adds them to your entry in every group you are in, so that the others can pay you back: they get them like the rest of the group — end-to-end encrypted over Matrix, and for groups you share with an invite link in the encrypted copies on the Nostr relays, readable by anyone with that group\'s link. Groups that exist only on this device (local mode) get nothing. The balance page shows them as a GiroCode or a PayPal.me link with the amount — on your screen and on the screen of someone who owes you. Removing or changing them in the settings updates your groups, but earlier copies stay in the others\' version history, backups and restore points (and on the relays until they expire). They are not part of a CSV. Deleting local data or uninstalling the app removes this device\'s copy; signing out keeps it.';

  @override
  String get paymentDetailsPageTitle => 'Payment details';

  @override
  String get payerSeveral => 'Several people…';

  @override
  String get payersHint => 'Who paid how much? Leave empty who didn\'t pay.';

  @override
  String paidByTwo(Object first, Object second) {
    return 'Paid by $first and $second';
  }

  @override
  String paidByMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Paid by $count people',
    );
    return '$_temp0';
  }

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsBody =>
      'Tell me when others add, change or delete expenses or payments (checked during background sync).';

  @override
  String get notificationsNeedBackgroundSync =>
      'Needs background sync — turn it on above.';

  @override
  String get notificationsBlocked =>
      'Notifications are blocked for MoneyLedger — allow them in Android\'s app settings.';

  @override
  String get notificationChannelName => 'Changes by others';

  @override
  String get notificationChannelDescription =>
      'When someone adds, changes or deletes an expense or payment in your groups.';

  @override
  String get notifySomeone => 'Someone';

  @override
  String get notifyAnExpense => 'an expense';

  @override
  String notifyExpenseAdded(String name, String what, String amount) {
    return '$name added $what · $amount';
  }

  @override
  String notifyExpenseEdited(String name, String what) {
    return '$name changed $what';
  }

  @override
  String notifyExpenseDeleted(String name, String what) {
    return '$name deleted $what';
  }

  @override
  String notifyPaymentAdded(
    String name,
    String from,
    String to,
    String amount,
  ) {
    return '$name recorded a payment: $from → $to · $amount';
  }

  @override
  String notifyPaymentEdited(String name, String from, String to) {
    return '$name changed a payment: $from → $to';
  }

  @override
  String notifyPaymentDeleted(String name, String from, String to) {
    return '$name deleted a payment: $from → $to';
  }

  @override
  String notifySeveralChanges(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes by $names',
      one: '1 change by $names',
    );
    return '$_temp0';
  }

  @override
  String notifyAddedToGroup(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You were added to this group — $count entries.',
      one: 'You were added to this group — 1 entry.',
      zero: 'You were added to this group.',
    );
    return '$_temp0';
  }

  @override
  String linkReplacedBanner(String name) {
    return '$name replaced this group\'s invite link. Ask someone in the group for the new link and open it here — until then you won\'t get $name\'s changes.';
  }

  @override
  String get linkReplacedBannerNoName =>
      'This group\'s invite link was replaced. Ask someone in the group for the new link and open it here — until then you may miss changes.';

  @override
  String get linkReplacedBannerMe =>
      'You replaced this group\'s invite link on another device. Open the new link here too to keep syncing.';

  @override
  String get joinLinkReplacedTitle => 'This invite link was replaced';

  @override
  String get joinLinkReplacedBody =>
      'The group moved to a new invite link. Ask someone in the group to send it to you.';

  @override
  String get joinLinkPickReplaced =>
      'Someone replaced this invite link — you may only get an old copy. Better ask someone in the group for the new link.';

  @override
  String get joinLinkSwitchReplaced =>
      'This link was replaced by a newer one — it is probably the old link. Better keep your current link.';
}
