import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('de'),
  ];

  /// App name — not translated
  ///
  /// In en, this message translates to:
  /// **'MoneyLedger'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// Snackbar after a failed action; error is technical text
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String failedWithError(Object error);

  /// No description provided for @errorWithDetail.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorWithDetail(Object error);

  /// No description provided for @groupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groupsTitle;

  /// No description provided for @importCsvTooltip.
  ///
  /// In en, this message translates to:
  /// **'Import CSV'**
  String get importCsvTooltip;

  /// No description provided for @devicesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Devices & security'**
  String get devicesTooltip;

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @signOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOutConfirmTitle;

  /// No description provided for @signOutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your groups and expenses stay on this device and are back when you sign in again with this account. While signed out, this device doesn\'t sync — other members\' changes arrive once you sign back in.'**
  String get signOutConfirmBody;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(Object error);

  /// No description provided for @importedExpenses.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 expense} other{Imported {count} expenses}}'**
  String importedExpenses(int count);

  /// No description provided for @noGroupsYet.
  ///
  /// In en, this message translates to:
  /// **'No groups yet.\nCreate one to get started.'**
  String get noGroupsYet;

  /// No description provided for @restoringGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Restoring your groups from your other devices…'**
  String get restoringGroupsTitle;

  /// No description provided for @restoringGroupsBody.
  ///
  /// In en, this message translates to:
  /// **'Open MoneyLedger on another device signed in to this account — it sends your groups while the app is running there.'**
  String get restoringGroupsBody;

  /// No description provided for @syncSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get syncSettingsTitle;

  /// No description provided for @syncSettingsBody.
  ///
  /// In en, this message translates to:
  /// **'Devices exchange changes while MoneyLedger is open. Changes from others wait on your homeserver (encrypted) until this device picks them up.'**
  String get syncSettingsBody;

  /// No description provided for @backgroundSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Background sync'**
  String get backgroundSyncTitle;

  /// No description provided for @backgroundSyncBody.
  ///
  /// In en, this message translates to:
  /// **'Also sync about every 15 minutes while the app is closed (with network, not on low battery).'**
  String get backgroundSyncBody;

  /// No description provided for @noBackgroundSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'No background sync here'**
  String get noBackgroundSyncTitle;

  /// No description provided for @noBackgroundSyncBody.
  ///
  /// In en, this message translates to:
  /// **'In the browser, MoneyLedger syncs only while this tab is open. The Android app also syncs periodically in the background.'**
  String get noBackgroundSyncBody;

  /// Settings sheet, under the background-sync switch, when Android refused to register/cancel the periodic task; error is technical text
  ///
  /// In en, this message translates to:
  /// **'Background sync couldn\'t be set up on this device: {error}'**
  String backgroundSyncScheduleFailed(String error);

  /// Persistent banner on the groups page when the end-to-end encryption library (vodozemac) failed to load at startup
  ///
  /// In en, this message translates to:
  /// **'Encryption couldn\'t be started on this device, so syncing with other people and devices is off. Your groups stay available here. Restart the app; if this persists, reinstall or update it.'**
  String get encryptionUnavailableBanner;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About MoneyLedger'**
  String get aboutTitle;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @signOutAndRestart.
  ///
  /// In en, this message translates to:
  /// **'Sign out and restart'**
  String get signOutAndRestart;

  /// No description provided for @expensesTitle.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expensesTitle;

  /// No description provided for @addMember.
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get addMember;

  /// No description provided for @membersTitle.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersTitle;

  /// No description provided for @balanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balanceTitle;

  /// No description provided for @moreTooltip.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreTooltip;

  /// No description provided for @editGroup.
  ///
  /// In en, this message translates to:
  /// **'Edit group'**
  String get editGroup;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @leaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Leave group'**
  String get leaveGroup;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// No description provided for @addExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get addExpense;

  /// No description provided for @removedFromGroupBanner.
  ///
  /// In en, this message translates to:
  /// **'You were removed from this group. Its history stays readable here.'**
  String get removedFromGroupBanner;

  /// No description provided for @deleteFromThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Delete from this device'**
  String get deleteFromThisDevice;

  /// No description provided for @addedToGroupBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'ve been added to this group. Which participant are you?'**
  String get addedToGroupBanner;

  /// No description provided for @choose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get choose;

  /// No description provided for @noExpensesYet.
  ///
  /// In en, this message translates to:
  /// **'No expenses yet.'**
  String get noExpensesYet;

  /// No description provided for @thisGroup.
  ///
  /// In en, this message translates to:
  /// **'This group'**
  String get thisGroup;

  /// No description provided for @youLeftGroup.
  ///
  /// In en, this message translates to:
  /// **'You left \"{group}\"'**
  String youLeftGroup(Object group);

  /// No description provided for @deletedGroup.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{group}\"'**
  String deletedGroup(Object group);

  /// Snackbar when writing the CSV export failed (G15).
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(Object error);

  /// No description provided for @exportedFile.
  ///
  /// In en, this message translates to:
  /// **'Exported {fileName}'**
  String exportedFile(Object fileName);

  /// No description provided for @whichParticipantAreYou.
  ///
  /// In en, this message translates to:
  /// **'Which participant are you?'**
  String get whichParticipantAreYou;

  /// No description provided for @imSomeoneNew.
  ///
  /// In en, this message translates to:
  /// **'I\'m someone new'**
  String get imSomeoneNew;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @deleteExpenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete expense?'**
  String get deleteExpenseTitle;

  /// No description provided for @deleteExpenseBody.
  ///
  /// In en, this message translates to:
  /// **'\"{description}\" will be removed for all members.'**
  String deleteExpenseBody(Object description);

  /// No description provided for @deleteSettlementTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete settlement?'**
  String get deleteSettlementTitle;

  /// No description provided for @deleteSettlementBody.
  ///
  /// In en, this message translates to:
  /// **'\"{from} paid {to} {amount}\" will be removed for all members and the balance restored.'**
  String deleteSettlementBody(Object from, Object to, Object amount);

  /// No description provided for @matrixIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Matrix ID'**
  String get matrixIdLabel;

  /// No description provided for @addedMember.
  ///
  /// In en, this message translates to:
  /// **'Added {userId}'**
  String addedMember(Object userId);

  /// No description provided for @syncProblemTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sync problem — tap for details'**
  String get syncProblemTooltip;

  /// No description provided for @syncedWithAll.
  ///
  /// In en, this message translates to:
  /// **'Synced with all members'**
  String get syncedWithAll;

  /// No description provided for @peerHasNoDevice.
  ///
  /// In en, this message translates to:
  /// **'{peer} has no active device — will sync when they sign in'**
  String peerHasNoDevice(Object peer);

  /// No description provided for @waitingForPeer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {peer}…'**
  String waitingForPeer(Object peer);

  /// No description provided for @syncProblemTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync problem'**
  String get syncProblemTitle;

  /// No description provided for @syncProblemBody.
  ///
  /// In en, this message translates to:
  /// **'Could not reach other members. Your changes are saved on this device and will sync once the connection recovers.'**
  String get syncProblemBody;

  /// No description provided for @lastSynced.
  ///
  /// In en, this message translates to:
  /// **'Last synced {ago}'**
  String lastSynced(Object ago);

  /// No description provided for @lastError.
  ///
  /// In en, this message translates to:
  /// **'Last error: {error}'**
  String lastError(Object error);

  /// No description provided for @retryingSync.
  ///
  /// In en, this message translates to:
  /// **'Retrying sync…'**
  String get retryingSync;

  /// No description provided for @retryNow.
  ///
  /// In en, this message translates to:
  /// **'Retry now'**
  String get retryNow;

  /// No description provided for @agoJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get agoJustNow;

  /// No description provided for @agoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String agoMinutes(int n);

  /// No description provided for @agoHours.
  ///
  /// In en, this message translates to:
  /// **'{n} h ago'**
  String agoHours(int n);

  /// No description provided for @agoDays.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 day ago} other{{n} days ago}}'**
  String agoDays(int n);

  /// No description provided for @paidByName.
  ///
  /// In en, this message translates to:
  /// **'Paid by {name}'**
  String paidByName(Object name);

  /// No description provided for @expenseOptions.
  ///
  /// In en, this message translates to:
  /// **'Expense options'**
  String get expenseOptions;

  /// No description provided for @settlementTitle.
  ///
  /// In en, this message translates to:
  /// **'{from} paid {to}'**
  String settlementTitle(Object from, Object to);

  /// No description provided for @settlementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Settlement · {date}'**
  String settlementSubtitle(Object date);

  /// No description provided for @settlementOptions.
  ///
  /// In en, this message translates to:
  /// **'Settlement options'**
  String get settlementOptions;

  /// No description provided for @editExpense.
  ///
  /// In en, this message translates to:
  /// **'Edit expense'**
  String get editExpense;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// No description provided for @amountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amountLabel;

  /// No description provided for @invalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Invalid number'**
  String get invalidNumber;

  /// No description provided for @currencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currencyLabel;

  /// No description provided for @paidByLabel.
  ///
  /// In en, this message translates to:
  /// **'Paid by'**
  String get paidByLabel;

  /// No description provided for @splitEqual.
  ///
  /// In en, this message translates to:
  /// **'Equal'**
  String get splitEqual;

  /// No description provided for @splitExact.
  ///
  /// In en, this message translates to:
  /// **'Exact'**
  String get splitExact;

  /// No description provided for @splitShares.
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get splitShares;

  /// No description provided for @splitSelectAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Select at least one participant'**
  String get splitSelectAtLeastOne;

  /// No description provided for @splitEquallyAmong.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{Split equally among 1} other{Split equally among {n}}}'**
  String splitEquallyAmong(int n);

  /// No description provided for @splitAddsUpToTotal.
  ///
  /// In en, this message translates to:
  /// **'Adds up to the total'**
  String get splitAddsUpToTotal;

  /// Split editor: part of the total not yet assigned to anyone
  ///
  /// In en, this message translates to:
  /// **'{amount} left'**
  String splitLeft(Object amount);

  /// Split editor: the assigned amounts exceed the total by this much
  ///
  /// In en, this message translates to:
  /// **'{amount} too much'**
  String splitTooMuch(Object amount);

  /// No description provided for @splitPercentValue.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String splitPercentValue(Object value);

  /// No description provided for @splitEnterAmountFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter the amount first'**
  String get splitEnterAmountFirst;

  /// Split editor action: spread what is left over the open (empty or auto-filled) rows
  ///
  /// In en, this message translates to:
  /// **'Distribute'**
  String get splitDistribute;

  /// Split editor action: scale the entered amounts so they add up to the total
  ///
  /// In en, this message translates to:
  /// **'Rescale proportionally'**
  String get splitRescale;

  /// No description provided for @splitPutRestHere.
  ///
  /// In en, this message translates to:
  /// **'Put the rest here'**
  String get splitPutRestHere;

  /// No description provided for @splitShareMore.
  ///
  /// In en, this message translates to:
  /// **'One share more'**
  String get splitShareMore;

  /// No description provided for @splitShareLess.
  ///
  /// In en, this message translates to:
  /// **'One share less'**
  String get splitShareLess;

  /// No description provided for @splitOpenFieldsHint.
  ///
  /// In en, this message translates to:
  /// **'Empty fields share the rest · 0 = not involved'**
  String get splitOpenFieldsHint;

  /// No description provided for @splitByWeight.
  ///
  /// In en, this message translates to:
  /// **'Split by weight'**
  String get splitByWeight;

  /// No description provided for @splitEnterWeight.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one weight'**
  String get splitEnterWeight;

  /// No description provided for @splitAddsUpTo100.
  ///
  /// In en, this message translates to:
  /// **'Adds up to 100%'**
  String get splitAddsUpTo100;

  /// No description provided for @splitPercentMustTotal100.
  ///
  /// In en, this message translates to:
  /// **'Percentages must total 100%'**
  String get splitPercentMustTotal100;

  /// No description provided for @recordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get recordPayment;

  /// No description provided for @allSettledUp.
  ///
  /// In en, this message translates to:
  /// **'All settled up!'**
  String get allSettledUp;

  /// No description provided for @owesName.
  ///
  /// In en, this message translates to:
  /// **'owes {name}'**
  String owesName(Object name);

  /// No description provided for @paymentRecorded.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded'**
  String get paymentRecorded;

  /// No description provided for @paymentFromLabel.
  ///
  /// In en, this message translates to:
  /// **'From (paid)'**
  String get paymentFromLabel;

  /// No description provided for @paymentToLabel.
  ///
  /// In en, this message translates to:
  /// **'To (received)'**
  String get paymentToLabel;

  /// No description provided for @paymentExceedsDebt.
  ///
  /// In en, this message translates to:
  /// **'More than the {amount} owed'**
  String paymentExceedsDebt(Object amount);

  /// No description provided for @record.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get record;

  /// No description provided for @unsettledYouOwe.
  ///
  /// In en, this message translates to:
  /// **'You still owe {amount}.'**
  String unsettledYouOwe(Object amount);

  /// No description provided for @unsettledYouAreOwed.
  ///
  /// In en, this message translates to:
  /// **'You are still owed {amount}.'**
  String unsettledYouAreOwed(Object amount);

  /// No description provided for @leaveGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave group?'**
  String get leaveGroupTitle;

  /// No description provided for @deleteGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete group?'**
  String get deleteGroupTitle;

  /// No description provided for @leaveGroupBody.
  ///
  /// In en, this message translates to:
  /// **'\"{group}\" will be removed from this device and the other members will see that you left. Your expenses stay in their ledger.'**
  String leaveGroupBody(Object group);

  /// No description provided for @deleteGroupBody.
  ///
  /// In en, this message translates to:
  /// **'\"{group}\" and all its expenses will be permanently removed from this device.'**
  String deleteGroupBody(Object group);

  /// No description provided for @backupBeforeExitTip.
  ///
  /// In en, this message translates to:
  /// **'Tip: back up all groups first (Settings → Back up all groups).'**
  String get backupBeforeExitTip;

  /// No description provided for @backupBeforeExit.
  ///
  /// In en, this message translates to:
  /// **'Back up all groups first'**
  String get backupBeforeExit;

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @groupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupNameLabel;

  /// No description provided for @defaultCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Default currency'**
  String get defaultCurrencyLabel;

  /// No description provided for @defaultCurrencyHelper.
  ///
  /// In en, this message translates to:
  /// **'Only applies to new expenses — existing expenses keep their currency.'**
  String get defaultCurrencyHelper;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @inviteByMatrixId.
  ///
  /// In en, this message translates to:
  /// **'Invite by Matrix ID'**
  String get inviteByMatrixId;

  /// No description provided for @addPerson.
  ///
  /// In en, this message translates to:
  /// **'Add person'**
  String get addPerson;

  /// No description provided for @noMembers.
  ///
  /// In en, this message translates to:
  /// **'No members.'**
  String get noMembers;

  /// No description provided for @formerMembers.
  ///
  /// In en, this message translates to:
  /// **'Former members'**
  String get formerMembers;

  /// No description provided for @invite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// No description provided for @invitedMember.
  ///
  /// In en, this message translates to:
  /// **'Invited {userId}'**
  String invitedMember(Object userId);

  /// No description provided for @nameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Alex'**
  String get nameHint;

  /// No description provided for @matrixIdOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Matrix ID (optional)'**
  String get matrixIdOptionalLabel;

  /// No description provided for @matrixIdOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'@user:server — leave blank for a local person'**
  String get matrixIdOptionalHint;

  /// No description provided for @invalidMatrixId.
  ///
  /// In en, this message translates to:
  /// **'Invalid Matrix ID'**
  String get invalidMatrixId;

  /// No description provided for @formerMemberClaimed.
  ///
  /// In en, this message translates to:
  /// **'{matrixId} · former member'**
  String formerMemberClaimed(Object matrixId);

  /// No description provided for @formerMemberLocal.
  ///
  /// In en, this message translates to:
  /// **'Local · former member'**
  String get formerMemberLocal;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @readd.
  ///
  /// In en, this message translates to:
  /// **'Re-add'**
  String get readd;

  /// No description provided for @readdedMember.
  ///
  /// In en, this message translates to:
  /// **'Re-added {name}'**
  String readdedMember(Object name);

  /// No description provided for @localParticipant.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get localParticipant;

  /// No description provided for @options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @detachMatrixAccount.
  ///
  /// In en, this message translates to:
  /// **'Detach Matrix account'**
  String get detachMatrixAccount;

  /// No description provided for @linkMatrixAccount.
  ///
  /// In en, this message translates to:
  /// **'Link Matrix account'**
  String get linkMatrixAccount;

  /// No description provided for @removeFromGroup.
  ///
  /// In en, this message translates to:
  /// **'Remove from group'**
  String get removeFromGroup;

  /// No description provided for @removeMemberBody.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from this group?\n\nTheir expense history is kept; only their membership is cleared.'**
  String removeMemberBody(Object name);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @onboardingAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add anyone — Matrix or not'**
  String get onboardingAddTitle;

  /// No description provided for @onboardingAddBody.
  ///
  /// In en, this message translates to:
  /// **'Invite people by their Matrix ID, or add local participants by name and link an account later.'**
  String get onboardingAddBody;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @devicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devicesTitle;

  /// No description provided for @couldNotLoadDevices.
  ///
  /// In en, this message translates to:
  /// **'Could not load devices: {error}'**
  String couldNotLoadDevices(Object error);

  /// No description provided for @thisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get thisDevice;

  /// No description provided for @verified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// No description provided for @notVerified.
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get notVerified;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @verifyDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify {device}'**
  String verifyDeviceTitle(Object device);

  /// No description provided for @verifyCompareEmoji.
  ///
  /// In en, this message translates to:
  /// **'Confirm these emoji appear in the same order on the other device.'**
  String get verifyCompareEmoji;

  /// No description provided for @deviceVerified.
  ///
  /// In en, this message translates to:
  /// **'Device verified.'**
  String get deviceVerified;

  /// No description provided for @verificationFailed.
  ///
  /// In en, this message translates to:
  /// **'Verification failed.'**
  String get verificationFailed;

  /// No description provided for @verificationFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Verification failed: {error}.'**
  String verificationFailedWithError(Object error);

  /// No description provided for @emojiNoMatch.
  ///
  /// In en, this message translates to:
  /// **'They don\'t match'**
  String get emojiNoMatch;

  /// No description provided for @emojiMatch.
  ///
  /// In en, this message translates to:
  /// **'They match'**
  String get emojiMatch;

  /// No description provided for @onlyDevice.
  ///
  /// In en, this message translates to:
  /// **'This is your only device.'**
  String get onlyDevice;

  /// No description provided for @allDevicesVerified.
  ///
  /// In en, this message translates to:
  /// **'All your devices are verified.'**
  String get allDevicesVerified;

  /// No description provided for @devicesNeedVerification.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 device needs verification.} other{{count} devices need verification.}}'**
  String devicesNeedVerification(int count);

  /// No description provided for @authUnreachableTitle.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach {host}'**
  String authUnreachableTitle(Object host);

  /// No description provided for @authUnreachableHint.
  ///
  /// In en, this message translates to:
  /// **'The server may be down or the address mistyped — or you\'re offline. Check the homeserver address and your internet connection.'**
  String get authUnreachableHint;

  /// Login error title when the homeserver couldn't be reached and no host is known (server down, wrong address, or offline).
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server'**
  String get authUnreachableNoHostTitle;

  /// No description provided for @authTimeoutTitle.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to respond'**
  String get authTimeoutTitle;

  /// No description provided for @authTimeoutHint.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get authTimeoutHint;

  /// No description provided for @authNotAHomeserverTitle.
  ///
  /// In en, this message translates to:
  /// **'{host} doesn\'t look like a Matrix homeserver'**
  String authNotAHomeserverTitle(Object host);

  /// No description provided for @authNotAHomeserverHint.
  ///
  /// In en, this message translates to:
  /// **'Check the address — for example matrix.org.'**
  String get authNotAHomeserverHint;

  /// No description provided for @authWrongCredentialsTitle.
  ///
  /// In en, this message translates to:
  /// **'Wrong username or password'**
  String get authWrongCredentialsTitle;

  /// No description provided for @authWrongCredentialsHint.
  ///
  /// In en, this message translates to:
  /// **'Check both and try again.'**
  String get authWrongCredentialsHint;

  /// No description provided for @authDeactivatedTitle.
  ///
  /// In en, this message translates to:
  /// **'This account has been deactivated'**
  String get authDeactivatedTitle;

  /// No description provided for @authDeactivatedHint.
  ///
  /// In en, this message translates to:
  /// **'Contact your homeserver administrator, or use another account.'**
  String get authDeactivatedHint;

  /// No description provided for @authRateLimitedTitle.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts'**
  String get authRateLimitedTitle;

  /// No description provided for @authRateLimitedRetry.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Please wait 1 second and try again.} other{Please wait {seconds} seconds and try again.}}'**
  String authRateLimitedRetry(int seconds);

  /// No description provided for @authRateLimitedHint.
  ///
  /// In en, this message translates to:
  /// **'Please wait a moment and try again.'**
  String get authRateLimitedHint;

  /// No description provided for @authSsoTokenTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign-in link expired or invalid'**
  String get authSsoTokenTitle;

  /// No description provided for @authSsoTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Please start the sign-in again.'**
  String get authSsoTokenHint;

  /// No description provided for @authUsernameTakenTitle.
  ///
  /// In en, this message translates to:
  /// **'That username is already taken'**
  String get authUsernameTakenTitle;

  /// No description provided for @authUsernameTakenHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a different username.'**
  String get authUsernameTakenHint;

  /// No description provided for @authInvalidUsernameTitle.
  ///
  /// In en, this message translates to:
  /// **'That username isn\'t allowed'**
  String get authInvalidUsernameTitle;

  /// No description provided for @authInvalidUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'Use only lowercase letters, digits and . _ = - /'**
  String get authInvalidUsernameHint;

  /// No description provided for @authWeakPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Password is too weak'**
  String get authWeakPasswordTitle;

  /// No description provided for @authWeakPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Use a longer password with a mix of letters, digits and symbols.'**
  String get authWeakPasswordHint;

  /// No description provided for @authRegistrationDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'This homeserver doesn\'t allow sign-up here'**
  String get authRegistrationDisabledTitle;

  /// No description provided for @authRegistrationDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'Create your account on its website, then sign in.'**
  String get authRegistrationDisabledHint;

  /// No description provided for @authUnknownTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get authUnknownTitle;

  /// No description provided for @authUnknownHint.
  ///
  /// In en, this message translates to:
  /// **'Please try again. The details below may help.'**
  String get authUnknownHint;

  /// No description provided for @authErrorDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get authErrorDetails;

  /// No description provided for @signInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your Matrix account'**
  String get signInSubtitle;

  /// No description provided for @homeserverLabel.
  ///
  /// In en, this message translates to:
  /// **'Homeserver'**
  String get homeserverLabel;

  /// No description provided for @homeserverHint.
  ///
  /// In en, this message translates to:
  /// **'matrix.org or mozilla.modular.im'**
  String get homeserverHint;

  /// Tooltip of the button next to the homeserver field that loads the server's sign-in options (nothing is requested before the user acts).
  ///
  /// In en, this message translates to:
  /// **'Check server'**
  String get checkServerTooltip;

  /// No description provided for @resolvedTo.
  ///
  /// In en, this message translates to:
  /// **'Resolved to {url}'**
  String resolvedTo(Object url);

  /// No description provided for @continueWith.
  ///
  /// In en, this message translates to:
  /// **'Continue with {provider}'**
  String continueWith(Object provider);

  /// No description provided for @orDivider.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get orDivider;

  /// No description provided for @matrixIdOrUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Matrix ID or username'**
  String get matrixIdOrUsernameLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @createAccountLink.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account'**
  String get createAccountLink;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get passwordMinLength;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get alreadyHaveAccount;

  /// No description provided for @registerOnWebTitle.
  ///
  /// In en, this message translates to:
  /// **'Register on the web'**
  String get registerOnWebTitle;

  /// No description provided for @registerOnWebBody.
  ///
  /// In en, this message translates to:
  /// **'This homeserver requires {requirements}, which MoneyLedger can\'t do in-app yet. Create your account on its website, then come back and sign in.'**
  String registerOnWebBody(Object requirements);

  /// No description provided for @openHomeserverWebsite.
  ///
  /// In en, this message translates to:
  /// **'Open homeserver website'**
  String get openHomeserverWebsite;

  /// Joins the last item of a list
  ///
  /// In en, this message translates to:
  /// **'{first} and {last}'**
  String listAnd(Object first, Object last);

  /// No description provided for @regReqExtraVerification.
  ///
  /// In en, this message translates to:
  /// **'extra verification'**
  String get regReqExtraVerification;

  /// No description provided for @regReqCaptcha.
  ///
  /// In en, this message translates to:
  /// **'a CAPTCHA'**
  String get regReqCaptcha;

  /// No description provided for @regReqEmail.
  ///
  /// In en, this message translates to:
  /// **'email verification'**
  String get regReqEmail;

  /// No description provided for @regReqPhone.
  ///
  /// In en, this message translates to:
  /// **'phone verification'**
  String get regReqPhone;

  /// No description provided for @regReqTerms.
  ///
  /// In en, this message translates to:
  /// **'accepting the terms of service'**
  String get regReqTerms;

  /// No description provided for @regReqToken.
  ///
  /// In en, this message translates to:
  /// **'a registration token'**
  String get regReqToken;

  /// No description provided for @regReqWebSignup.
  ///
  /// In en, this message translates to:
  /// **'signing up on its own website'**
  String get regReqWebSignup;

  /// No description provided for @aboutAndPrivacy.
  ///
  /// In en, this message translates to:
  /// **'About & privacy'**
  String get aboutAndPrivacy;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(Object version);

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'Split expenses with friends — decentralized and end-to-end encrypted over Matrix. Your ledger stays on your devices; there is no MoneyLedger server.'**
  String get aboutDescription;

  /// No description provided for @aboutSourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSourceCode;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicense;

  /// No description provided for @aboutLicenseValue.
  ///
  /// In en, this message translates to:
  /// **'{license} — free software: you may use, study, share and modify it.'**
  String aboutLicenseValue(Object license);

  /// No description provided for @aboutLegalese.
  ///
  /// In en, this message translates to:
  /// **'© Leo Stumpf. Licensed under the {license}.'**
  String aboutLegalese(Object license);

  /// No description provided for @aboutOpenSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get aboutOpenSourceLicenses;

  /// No description provided for @privacyPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicyTitle;

  /// No description provided for @privacyLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated: {date}'**
  String privacyLastUpdated(Object date);

  /// No description provided for @privacyIntro.
  ///
  /// In en, this message translates to:
  /// **'MoneyLedger is an expense-sharing app without a central server. It has no account system of its own — you sign in with your Matrix account, or use the app without any account (local mode) — shows no ads, contains no analytics or tracking, and does not sell or share your data. MoneyLedger is published by Leo Stumpf, an individual developer. There is no MoneyLedger server that could receive your data.'**
  String get privacyIntro;

  /// No description provided for @privacyLedgerTitle.
  ///
  /// In en, this message translates to:
  /// **'Your ledger stays on your devices'**
  String get privacyLedgerTitle;

  /// No description provided for @privacyLedgerBody.
  ///
  /// In en, this message translates to:
  /// **'Groups, participants, expenses and payments are stored only in a local database on each device signed in to a member\'s account. Every member of a group has a copy of that group\'s ledger — that is how sharing works: the names, Matrix IDs, expenses and payments in a group are visible to all of its members.'**
  String get privacyLedgerBody;

  /// No description provided for @privacyHomeserverTitle.
  ///
  /// In en, this message translates to:
  /// **'What your Matrix homeserver sees'**
  String get privacyHomeserverTitle;

  /// No description provided for @privacyHomeserverBody.
  ///
  /// In en, this message translates to:
  /// **'To sync, MoneyLedger sends every change as an end-to-end-encrypted Matrix to-device message to the other members\' devices. Your homeserver (and the homeservers of the other members) relay these messages and keep each one only until the receiving device has fetched it, but cannot read them. They do see metadata: which accounts and devices exchange messages, when, how often and roughly how large they are. MoneyLedger creates no rooms, saves nothing in your account\'s settings and never marks you as online; when it syncs, it asks your homeserver only for these messages and for encryption-key updates — not for your rooms, presence or account settings. What your homeserver still keeps is what every Matrix app needs: your account, its list of devices (this one is named “MoneyLedger”, with when and from which IP address it was last used), each device\'s public encryption keys and one-time keys, and the messages above until they are delivered (for a device that never comes back, until it is removed). Your Matrix account itself — user name, devices, encryption keys, IP addresses and sign-in history — is handled by your homeserver under its own privacy policy.'**
  String get privacyHomeserverBody;

  /// No description provided for @privacyNoTrackingTitle.
  ///
  /// In en, this message translates to:
  /// **'No analytics, no servers of ours'**
  String get privacyNoTrackingTitle;

  /// No description provided for @privacyNoTrackingBody.
  ///
  /// In en, this message translates to:
  /// **'The app talks only to Matrix homeservers: on the sign-in page to the server you enter — and only once you confirm it or sign in — and after that only to your own homeserver. Through it, the app also looks up the Matrix profile names and devices of your groups\' members (your homeserver may ask theirs). If you use single sign-on or sign up on the web, your browser opens the pages your homeserver sends you to (for matrix.org possibly Element\'s sign-up page, app.element.io). Links in the app — to the source code on GitHub, for example — open in your browser only when you tap them. The web version is loaded entirely from the site that hosts it: no code or fonts from Google or any other third party. There is no analytics, no crash reporting, no advertising ID and no tracking of any kind.'**
  String get privacyNoTrackingBody;

  /// No description provided for @privacyBackgroundTitle.
  ///
  /// In en, this message translates to:
  /// **'Background sync on Android'**
  String get privacyBackgroundTitle;

  /// No description provided for @privacyBackgroundBody.
  ///
  /// In en, this message translates to:
  /// **'On Android, MoneyLedger can sync about every 15 minutes while the app is closed (only with a network connection and not on low battery). It uses the same encrypted messages to your homeserver and shows no notifications. You can turn it off in Settings. The web version syncs only while its tab is open.'**
  String get privacyBackgroundBody;

  /// No description provided for @privacyCsvTitle.
  ///
  /// In en, this message translates to:
  /// **'Export, backup and import'**
  String get privacyCsvTitle;

  /// No description provided for @privacyCsvBody.
  ///
  /// In en, this message translates to:
  /// **'Exporting a group writes a CSV file with its expenses, payments, the participants\' names and the amounts; a backup (\"Back up all groups\", or one group from its menu) writes one JSON file with the groups, including the participants\' Matrix IDs and deleted entries. Both happen only when you ask for it. Where the file goes is your choice. A CSV is always plain text; a backup is plain text too unless you set a passphrase — then it is encrypted on your device (Argon2id + AES-256-GCM) and can only be restored with that passphrase, which MoneyLedger never stores or sends anywhere. MoneyLedger has no visibility into the file afterwards. Importing or restoring reads only the file you pick.'**
  String get privacyCsvBody;

  /// No description provided for @privacyBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Device backups'**
  String get privacyBackupTitle;

  /// No description provided for @privacyBackupBody.
  ///
  /// In en, this message translates to:
  /// **'MoneyLedger opts out of Android\'s automatic app backup and device-to-device transfer. Your ledger and your Matrix session (including its encryption keys) are never copied into a Google backup or onto another phone by Android. On a new device, sign in and your groups are restored from your other devices and the other members; for groups only you use, a backup file (Settings → Back up all groups) is your own offline copy.'**
  String get privacyBackupBody;

  /// No description provided for @privacyDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleting your data'**
  String get privacyDeleteTitle;

  /// No description provided for @privacyDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'• Leave or delete a group (group menu ⋮): it and all its records are removed from this device (the daily restore points keep it for about five weeks — see above). When you leave, the other members are told that you left.\n• Signing out keeps this account\'s ledger on the device, so it is back when you sign in again.\n• In local mode, Settings → Delete local data removes every local group from this device and ends local mode.\n• Uninstalling the app (or clearing its storage) removes everything it stored on the device.\n• Copies on other members\' devices are theirs: they keep the group\'s history, including your expenses in it.\n• Your Matrix account can be deactivated through your homeserver.'**
  String get privacyDeleteBody;

  /// No description provided for @privacyContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get privacyContactTitle;

  /// No description provided for @privacyContactBody.
  ///
  /// In en, this message translates to:
  /// **'Questions, or anything that looks wrong here: open an issue at https://github.com/LeoStumpf/MoneyLedger or email leo.m.stumpf@gmail.com.'**
  String get privacyContactBody;

  /// No description provided for @youAreOwedAmount.
  ///
  /// In en, this message translates to:
  /// **'You are owed {amount}'**
  String youAreOwedAmount(String amount);

  /// No description provided for @youOweAmount.
  ///
  /// In en, this message translates to:
  /// **'You owe {amount}'**
  String youOweAmount(String amount);

  /// No description provided for @settledUp.
  ///
  /// In en, this message translates to:
  /// **'Settled up'**
  String get settledUp;

  /// No description provided for @notParticipating.
  ///
  /// In en, this message translates to:
  /// **'Not a participant'**
  String get notParticipating;

  /// No description provided for @lastActivity.
  ///
  /// In en, this message translates to:
  /// **'Last activity {date}'**
  String lastActivity(String date);

  /// No description provided for @totalOwedLabel.
  ///
  /// In en, this message translates to:
  /// **'You are owed'**
  String get totalOwedLabel;

  /// No description provided for @totalOwingLabel.
  ///
  /// In en, this message translates to:
  /// **'You owe'**
  String get totalOwingLabel;

  /// No description provided for @totalNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing'**
  String get totalNothing;

  /// No description provided for @overallSettledUp.
  ///
  /// In en, this message translates to:
  /// **'You\'re all settled up'**
  String get overallSettledUp;

  /// No description provided for @overviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Across all groups'**
  String get overviewTitle;

  /// No description provided for @groupsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get groupsEmptyTitle;

  /// No description provided for @groupsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Create a group for a trip, your flat or a dinner out — then add the people you share costs with.'**
  String get groupsEmptyBody;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroup;

  /// No description provided for @importCsv.
  ///
  /// In en, this message translates to:
  /// **'Import CSV'**
  String get importCsv;

  /// No description provided for @membersCount.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 member} other{{n} members}}'**
  String membersCount(int n);

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @youPaid.
  ///
  /// In en, this message translates to:
  /// **'You paid'**
  String get youPaid;

  /// No description provided for @youLentAmount.
  ///
  /// In en, this message translates to:
  /// **'you lent {amount}'**
  String youLentAmount(String amount);

  /// No description provided for @youBorrowedAmount.
  ///
  /// In en, this message translates to:
  /// **'you borrowed {amount}'**
  String youBorrowedAmount(String amount);

  /// No description provided for @notInvolved.
  ///
  /// In en, this message translates to:
  /// **'not involved'**
  String get notInvolved;

  /// No description provided for @settlementYouPaid.
  ///
  /// In en, this message translates to:
  /// **'You paid {to}'**
  String settlementYouPaid(String to);

  /// No description provided for @settlementPaidYou.
  ///
  /// In en, this message translates to:
  /// **'{from} paid you'**
  String settlementPaidYou(String from);

  /// No description provided for @paymentLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get paymentLabel;

  /// No description provided for @yourBalance.
  ///
  /// In en, this message translates to:
  /// **'Your balance'**
  String get yourBalance;

  /// No description provided for @settleUp.
  ///
  /// In en, this message translates to:
  /// **'Settle up'**
  String get settleUp;

  /// No description provided for @balancesButton.
  ///
  /// In en, this message translates to:
  /// **'Balances'**
  String get balancesButton;

  /// No description provided for @balancesSection.
  ///
  /// In en, this message translates to:
  /// **'Balances'**
  String get balancesSection;

  /// No description provided for @suggestedPayments.
  ///
  /// In en, this message translates to:
  /// **'Suggested payments'**
  String get suggestedPayments;

  /// No description provided for @suggestedPaymentsHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a payment once it has been made to record it.'**
  String get suggestedPaymentsHint;

  /// No description provided for @balanceGetsBack.
  ///
  /// In en, this message translates to:
  /// **'gets back'**
  String get balanceGetsBack;

  /// No description provided for @balanceOwes.
  ///
  /// In en, this message translates to:
  /// **'owes'**
  String get balanceOwes;

  /// No description provided for @balanceYouGetBack.
  ///
  /// In en, this message translates to:
  /// **'you get back'**
  String get balanceYouGetBack;

  /// No description provided for @balanceYouOwe.
  ///
  /// In en, this message translates to:
  /// **'you owe'**
  String get balanceYouOwe;

  /// No description provided for @balanceSettled.
  ///
  /// In en, this message translates to:
  /// **'settled up'**
  String get balanceSettled;

  /// No description provided for @debtPays.
  ///
  /// In en, this message translates to:
  /// **'{from} pays {to}'**
  String debtPays(String from, String to);

  /// No description provided for @allSettledUpBody.
  ///
  /// In en, this message translates to:
  /// **'Nobody in this group owes anybody anything.'**
  String get allSettledUpBody;

  /// No description provided for @expensesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No expenses yet'**
  String get expensesEmptyTitle;

  /// No description provided for @expensesEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add the first expense — MoneyLedger works out who owes whom.'**
  String get expensesEmptyBody;

  /// Empty ledger of a group whose only participant is the user (G46)
  ///
  /// In en, this message translates to:
  /// **'It\'s just you so far. Add the people you share costs with, then the first expense.'**
  String get expensesEmptyAloneBody;

  /// Call to action on an empty group with only the user in it (G46)
  ///
  /// In en, this message translates to:
  /// **'Add people'**
  String get addPeople;

  /// No description provided for @splitSection.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get splitSection;

  /// No description provided for @nameOptionalHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional with a Matrix ID — their profile name is used'**
  String get nameOptionalHelper;

  /// No description provided for @nameOrMatrixIdRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name or a Matrix ID'**
  String get nameOrMatrixIdRequired;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @localPerson.
  ///
  /// In en, this message translates to:
  /// **'Local person'**
  String get localPerson;

  /// No description provided for @debtYouPay.
  ///
  /// In en, this message translates to:
  /// **'You pay {to}'**
  String debtYouPay(String to);

  /// No description provided for @debtPaysYou.
  ///
  /// In en, this message translates to:
  /// **'{from} pays you'**
  String debtPaysYou(String from);

  /// No description provided for @backupSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupSectionTitle;

  /// No description provided for @backupExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Back up all groups'**
  String get backupExportTitle;

  /// No description provided for @backupExportBody.
  ///
  /// In en, this message translates to:
  /// **'Saves every group — with payments and deleted entries — to one file, optionally encrypted with a passphrase. Without one the file is plain text: keep it somewhere safe.'**
  String get backupExportBody;

  /// No description provided for @backupRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from backup'**
  String get backupRestoreTitle;

  /// No description provided for @backupRestoreBody.
  ///
  /// In en, this message translates to:
  /// **'Merges a backup file into this device. Newer entries win; nothing is duplicated.'**
  String get backupRestoreBody;

  /// No description provided for @lastBackupAt.
  ///
  /// In en, this message translates to:
  /// **'Last backup: {date}'**
  String lastBackupAt(String date);

  /// No description provided for @lastBackupNever.
  ///
  /// In en, this message translates to:
  /// **'Last backup: never'**
  String get lastBackupNever;

  /// No description provided for @backupSaved.
  ///
  /// In en, this message translates to:
  /// **'Backup saved: {fileName}'**
  String backupSaved(String fileName);

  /// No description provided for @backupNotABackup.
  ///
  /// In en, this message translates to:
  /// **'This file is not a MoneyLedger backup.'**
  String get backupNotABackup;

  /// No description provided for @backupNewerVersion.
  ///
  /// In en, this message translates to:
  /// **'This backup was made by a newer version of MoneyLedger (format {version}). Update the app to restore it.'**
  String backupNewerVersion(int version);

  /// No description provided for @backupMalformed.
  ///
  /// In en, this message translates to:
  /// **'This backup file is damaged and can\'t be restored.'**
  String get backupMalformed;

  /// No description provided for @restorePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore backup?'**
  String get restorePreviewTitle;

  /// No description provided for @restoreBackupFrom.
  ///
  /// In en, this message translates to:
  /// **'Backup from {date}'**
  String restoreBackupFrom(String date);

  /// No description provided for @restoreOtherAccount.
  ///
  /// In en, this message translates to:
  /// **'This backup was made by {account}. Its groups will be added to the account you are signed in with.'**
  String restoreOtherAccount(String account);

  /// G41 restore preview: a local-mode backup is restored into a signed-in Matrix account.
  ///
  /// In en, this message translates to:
  /// **'This backup was made without a Matrix account. Restoring it moves its groups into {account}: you become their member there, and this device signs your entries so they can sync.'**
  String restoreLocalIntoAccount(String account);

  /// G41 restore preview: a Matrix account's backup is restored in local mode (no account).
  ///
  /// In en, this message translates to:
  /// **'This backup belongs to the Matrix account {account}. Here you take that account\'s place in its groups; nothing is sent. Connect {account} later to sync them again.'**
  String restoreAccountIntoLocal(String account);

  /// G18 review 2 restore preview warning: a local-mode backup restored into a Matrix account — its entries get signed by this device.
  ///
  /// In en, this message translates to:
  /// **'Only restore a backup you made yourself: this device signs its entries as yours. Groups that include Matrix accounts are restored unsigned and won\'t sync.'**
  String get restoreLocalOwnFile;

  /// No description provided for @groupsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 group} other{{count} groups}}'**
  String groupsCount(int count);

  /// No description provided for @expensesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 expense} other{{count} expenses}}'**
  String expensesCount(int count);

  /// No description provided for @paymentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 payment} other{{count} payments}}'**
  String paymentsCount(int count);

  /// No description provided for @restoreNewGroups.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No new groups} =1{1 new group} other{{count} new groups}}'**
  String restoreNewGroups(int count);

  /// No description provided for @restoreChanges.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Everything in this backup is already on this device.} =1{1 entry will be added or updated.} other{{count} entries will be added or updated.}}'**
  String restoreChanges(int count);

  /// No description provided for @restoreTagNew.
  ///
  /// In en, this message translates to:
  /// **'new'**
  String get restoreTagNew;

  /// No description provided for @restoreTagLeft.
  ///
  /// In en, this message translates to:
  /// **'left earlier — comes back'**
  String get restoreTagLeft;

  /// No description provided for @restoreTagChanges.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change} other{{count} changes}}'**
  String restoreTagChanges(int count);

  /// No description provided for @restoreTagUpToDate.
  ///
  /// In en, this message translates to:
  /// **'up to date'**
  String get restoreTagUpToDate;

  /// No description provided for @restoreLeftNote.
  ///
  /// In en, this message translates to:
  /// **'Groups you left or deleted come back on this device. If the other members removed you from a group, it comes back read-only (history only) — a removal after this backup shows up at the next sync.'**
  String get restoreLeftNote;

  /// No description provided for @restoreAction.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreAction;

  /// No description provided for @restoredGroups.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Restored 1 group} other{Restored {count} groups}}'**
  String restoredGroups(int count);

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String restoreFailed(String error);

  /// No description provided for @backupNudgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Back up your groups'**
  String get backupNudgeTitle;

  /// No description provided for @backupNudgeBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 group exists only on this device. If you lose it, the group is gone — save a backup file.} other{{count} groups exist only on this device. If you lose it, they are gone — save a backup file.}}'**
  String backupNudgeBody(int count);

  /// No description provided for @backupNudgeLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get backupNudgeLater;

  /// No description provided for @backupNudgeAction.
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backupNudgeAction;

  /// No description provided for @onboardingBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep a copy'**
  String get onboardingBackupTitle;

  /// No description provided for @onboardingBackupBody.
  ///
  /// In en, this message translates to:
  /// **'Nobody else stores your ledger. Groups with other members are copied to their devices. For groups only you use, sign in on a second device too, or save a backup now and then (Settings → Back up all groups).'**
  String get onboardingBackupBody;

  /// No description provided for @csvPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Import CSV?'**
  String get csvPreviewTitle;

  /// No description provided for @csvPreviewNewGroup.
  ///
  /// In en, this message translates to:
  /// **'Creates the new group “{name}”.'**
  String csvPreviewNewGroup(String name);

  /// No description provided for @csvPreviewExistingGroup.
  ///
  /// In en, this message translates to:
  /// **'Merges into your group “{name}”. Newer entries win.'**
  String csvPreviewExistingGroup(String name);

  /// No description provided for @csvPreviewUnmatched.
  ///
  /// In en, this message translates to:
  /// **'Not found in the group — will be added as new people: {names}'**
  String csvPreviewUnmatched(String names);

  /// No description provided for @csvPreviewAmbiguous.
  ///
  /// In en, this message translates to:
  /// **'Several participants have the same name — the active one is used: {names}'**
  String csvPreviewAmbiguous(String names);

  /// No description provided for @csvImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get csvImportAction;

  /// No description provided for @csvImportEmpty.
  ///
  /// In en, this message translates to:
  /// **'This CSV contains no expenses or payments.'**
  String get csvImportEmpty;

  /// No description provided for @importedExpensesAndPayments.
  ///
  /// In en, this message translates to:
  /// **'Imported {expenses} and {payments}'**
  String importedExpensesAndPayments(String expenses, String payments);

  /// G6: who created an expense/payment (signed origin)
  ///
  /// In en, this message translates to:
  /// **'Added by {name}'**
  String recordAddedBy(String name);

  /// G6: who signed the current version
  ///
  /// In en, this message translates to:
  /// **'Last edited by {name}'**
  String recordEditedBy(String name);

  /// G6: who recorded a payment
  ///
  /// In en, this message translates to:
  /// **'Recorded by {name}'**
  String recordRecordedBy(String name);

  /// G6: the current user as editor, e.g. 'Added by you'
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get recordYou;

  /// G6: a pre-G6 record without signature
  ///
  /// In en, this message translates to:
  /// **'Saved by an older app version (unsigned)'**
  String get recordUnsigned;

  /// G6
  ///
  /// In en, this message translates to:
  /// **'Signature not verifiable — the signing device may have signed out'**
  String get recordSigUnverified;

  /// G6: details sheet
  ///
  /// In en, this message translates to:
  /// **'Verified on receipt against the device\'s key'**
  String get recordSigVerified;

  /// G6: key vouched for by a snapshot sender
  ///
  /// In en, this message translates to:
  /// **'Device confirmed by {name}'**
  String recordSigVouched(String name);

  /// G6: key conflict
  ///
  /// In en, this message translates to:
  /// **'Signature doesn\'t match {name}\'s device'**
  String recordSigConflict(String name);

  /// G6: impersonation warning
  ///
  /// In en, this message translates to:
  /// **'Claims to be from you, but not from one of your devices'**
  String get recordNotYourDevice;

  /// G6: notice on the edit page
  ///
  /// In en, this message translates to:
  /// **'A newer version relayed by {relay} was refused: it claims to be from {name} but isn\'t validly signed by their device.'**
  String recordVersionRejected(String relay, String name);

  /// G6: details sheet
  ///
  /// In en, this message translates to:
  /// **'Signed by device {device} · {date}'**
  String recordSignedByDevice(String device, String date);

  /// G6: details sheet title / tooltip
  ///
  /// In en, this message translates to:
  /// **'Signature details'**
  String get recordSignatureDetails;

  /// G6: list icon tooltip
  ///
  /// In en, this message translates to:
  /// **'Signature problem'**
  String get recordSignatureWarning;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'{peer} has no verified device — verify one to sync (only verified devices are synced)'**
  String peerHasNoVerifiedDevice(Object peer);

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'Only sync with verified devices'**
  String get verifiedOnlyTitle;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'Off: every device of your group members (and your own) receives your ledger data.'**
  String get verifiedOnlyOffBody;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'On: this device sends nothing to devices you haven\'t verified by emoji comparison — yours or other members\'. It only limits what this device sends: other devices keep syncing with each other, and a new login of yours can\'t restore your groups from this device until you verify it.'**
  String get verifiedOnlyOnBody;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'Only sync with verified devices?'**
  String get verifiedOnlyConfirmTitle;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'This only limits what this device sends: your expenses, payments and group changes go only to devices you have verified by comparing emojis (Devices page for your own, the members page for others). It doesn\'t change what other devices send — members\' devices, and your other devices, keep syncing with each other unless they turn this on too.\n\nUnverified devices — including a member\'s new phone — get nothing from this device until you verify them, so they fall behind.\n\nA new login of your own can\'t restore your groups from this device until you verify it on the Devices page.\n\nRecords you receive are still accepted; the details show whether the signing device is verified. Applies to this device and account only.'**
  String get verifiedOnlyConfirmBody;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get verifiedOnlyTurnOn;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unverified device} other{{count} unverified devices}}'**
  String memberUnverifiedDevices(int count);

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'Not reachable — no verified device'**
  String get memberNotReachableUnverified;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'Devices of {name}'**
  String memberDevicesTitle(Object name);

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'Verify a device by comparing emojis with its owner (in person or on a call). Verification is stored on this device only.'**
  String get memberDevicesBody;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'No active devices.'**
  String get memberHasNoDevices;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'Verification request'**
  String get incomingVerificationTitle;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'Your device {device} wants to verify this device by comparing emojis.'**
  String incomingVerificationOwnDevice(Object device);

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'{user} (device {device}) wants to verify this device by comparing emojis.'**
  String incomingVerificationMember(Object user, Object device);

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'You verified this device (emoji comparison).'**
  String get recordDeviceVerifiedByYou;

  /// G11 device-verification enforcement
  ///
  /// In en, this message translates to:
  /// **'You haven\'t verified this device (emoji comparison).'**
  String get recordDeviceNotVerifiedByYou;

  /// G16 expense categories
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryLabel;

  /// G16 expense categories
  ///
  /// In en, this message translates to:
  /// **'Food & drink'**
  String get categoryFood;

  /// G16 expense categories
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get categoryGroceries;

  /// G16 expense categories
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get categoryTransport;

  /// G16 expense categories
  ///
  /// In en, this message translates to:
  /// **'Accommodation'**
  String get categoryAccommodation;

  /// G16 expense categories
  ///
  /// In en, this message translates to:
  /// **'Entertainment'**
  String get categoryEntertainment;

  /// G16 expense categories
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get categoryShopping;

  /// G16 expense categories
  ///
  /// In en, this message translates to:
  /// **'Home & utilities'**
  String get categoryHome;

  /// G16 expense categories
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get categoryHealth;

  /// G16 expense categories
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get categoryTravel;

  /// G16 expense categories
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get categoryOther;

  /// G16 expense note field
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get noteLabel;

  /// G16 tooltip of the note icon in the expense list
  ///
  /// In en, this message translates to:
  /// **'Has a note'**
  String get expenseHasNote;

  /// G16 expense search / filter
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTooltip;

  /// G16 expense search / filter
  ///
  /// In en, this message translates to:
  /// **'Search description, note, payer'**
  String get searchHint;

  /// G16 expense search / filter
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// G16 expense search / filter
  ///
  /// In en, this message translates to:
  /// **'Involving me'**
  String get filterInvolvingMe;

  /// G16 expense search / filter
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get noMatchesTitle;

  /// G16 expense search / filter
  ///
  /// In en, this message translates to:
  /// **'Try another search or clear the filters.'**
  String get noMatchesBody;

  /// G16 expense search / filter
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// G16 expense search / filter
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry} other{{count} entries}}'**
  String filterResultCount(int count);

  /// G16 archived groups (device-local)
  ///
  /// In en, this message translates to:
  /// **'Archive group'**
  String get archiveGroup;

  /// G16 archived groups (device-local)
  ///
  /// In en, this message translates to:
  /// **'Unarchive group'**
  String get unarchiveGroup;

  /// G16 archived groups (device-local)
  ///
  /// In en, this message translates to:
  /// **'Archived ({count})'**
  String archivedSection(int count);

  /// G16 archived groups (device-local)
  ///
  /// In en, this message translates to:
  /// **'Only hidden on this device. A group comes back by itself when something new is added.'**
  String get archivedSectionHint;

  /// G16 archived groups (device-local)
  ///
  /// In en, this message translates to:
  /// **'“{name}” archived'**
  String groupArchived(String name);

  /// G16 archived groups (device-local)
  ///
  /// In en, this message translates to:
  /// **'“{name}” archived — your open balance still counts in the totals.'**
  String groupArchivedUnsettled(String name);

  /// G16 archived groups (device-local)
  ///
  /// In en, this message translates to:
  /// **'“{name}” is back in your groups'**
  String groupUnarchived(String name);

  /// G16 archived groups (device-local)
  ///
  /// In en, this message translates to:
  /// **'This group is archived on this device.'**
  String get archivedBanner;

  /// G16 archived groups (device-local)
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// G16 settle-up explanation (simplify debts)
  ///
  /// In en, this message translates to:
  /// **'How are payments suggested?'**
  String get simplifyDebtsInfoTooltip;

  /// G16 settle-up explanation (simplify debts)
  ///
  /// In en, this message translates to:
  /// **'Simplified debts'**
  String get simplifyDebtsInfoTitle;

  /// G16 settle-up explanation (simplify debts)
  ///
  /// In en, this message translates to:
  /// **'MoneyLedger adds up all expenses and payments into one balance per person and suggests the fewest payments that settle everyone up. So you might pay someone you never shared an expense with directly — the amounts everyone pays and gets back stay exactly the same.\n\nEach currency is settled on its own: amounts are never converted.'**
  String get simplifyDebtsInfoBody;

  /// G16 settle-up explanation (simplify debts)
  ///
  /// In en, this message translates to:
  /// **'Settled separately per currency — amounts are never converted.'**
  String get simplifyDebtsPerCurrency;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Protect the backup?'**
  String get backupPassphraseTitle;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'You can encrypt the file with a passphrase. Leave it empty to save it unencrypted.'**
  String get backupPassphraseBody;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Passphrase (optional)'**
  String get backupPassphraseLabel;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Repeat passphrase'**
  String get backupPassphraseConfirmLabel;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'The passphrases don\'t match'**
  String get backupPassphraseMismatch;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Strength: weak — use a longer one, e.g. four random words'**
  String get backupPassphraseWeak;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Strength: fair'**
  String get backupPassphraseFair;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Strength: strong'**
  String get backupPassphraseStrong;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Without a passphrase the file is not encrypted: anyone who gets it can read all its groups.'**
  String get backupPlaintextWarning;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Don\'t lose the passphrase — without it the backup can\'t be restored, and nobody can recover it.'**
  String get backupPassphraseKeepSafe;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Encrypting…'**
  String get backupEncrypting;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Decrypting…'**
  String get backupDecrypting;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup'**
  String get backupUnlockTitle;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Enter the passphrase this backup was saved with.'**
  String get backupUnlockBody;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get backupUnlockLabel;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get backupUnlockAction;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Wrong passphrase — or the file was changed. Try again.'**
  String get backupWrongPassphrase;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupSavedNoName;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup saved: {fileName}'**
  String backupSavedEncrypted(String fileName);

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup saved'**
  String get backupSavedEncryptedNoName;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'CSV exported'**
  String get exportedNoName;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Back up this group'**
  String get backupThisGroup;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Show passphrase'**
  String get showPassphrase;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Hide passphrase'**
  String get hidePassphrase;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup — unlocked with your passphrase.'**
  String get restoreEncryptedNote;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'read-only — you were removed'**
  String get restoreTagRemoved;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 group couldn\'t be restored and was left unchanged: {error}} other{{count} groups couldn\'t be restored and were left unchanged: {error}}}'**
  String restoreIncomplete(int count, String error);

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'Some data couldn\'t be received'**
  String get legacyRefusedTitle;

  /// G34/G35
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{sender} sent 1 entry of “{group}” that was saved by an older app version without a signature. It was refused, so the group is incomplete or missing here. Ask {sender} to recreate the group.} other{{sender} sent {count} entries of “{group}” that were saved by an older app version without a signature. They were refused, so the group is incomplete or missing here. Ask {sender} to recreate the group.}}'**
  String legacyRefusedBody(int count, String sender, String group);

  /// G36 debug-only settings action: queue one WorkManager background round
  ///
  /// In en, this message translates to:
  /// **'Run background sync now (debug)'**
  String get debugRunBackgroundSync;

  /// G36 debug-only settings action subtitle
  ///
  /// In en, this message translates to:
  /// **'Queues one background round in {seconds} s — close the app to test it headless.'**
  String debugRunBackgroundSyncBody(int seconds);

  /// G36 debug-only snackbar
  ///
  /// In en, this message translates to:
  /// **'Background round queued.'**
  String get debugRunBackgroundSyncQueued;

  /// G36: a second sign-in/registration attempt while the previous (timed-out) request is still running
  ///
  /// In en, this message translates to:
  /// **'Still signing in…'**
  String get authInProgressTitle;

  /// G36 hint for authInProgressTitle
  ///
  /// In en, this message translates to:
  /// **'The previous attempt is still waiting for the server. If it succeeds you\'re signed in automatically — otherwise try again in a moment.'**
  String get authInProgressHint;

  /// G18: inviter picks the participant an invited account becomes
  ///
  /// In en, this message translates to:
  /// **'Who is {userId} in this group?'**
  String inviteWhoIs(Object userId);

  /// No description provided for @inviteAsNewParticipant.
  ///
  /// In en, this message translates to:
  /// **'A new participant'**
  String get inviteAsNewParticipant;

  /// G18: live preview of the parsed amount under an amount field, e.g. '= 1.234,00 €'
  ///
  /// In en, this message translates to:
  /// **'= {amount}'**
  String amountPreview(Object amount);

  /// No description provided for @amountMustBePositive.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than 0'**
  String get amountMustBePositive;

  /// No description provided for @amountTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That amount is too large'**
  String get amountTooLarge;

  /// No description provided for @finishingBackgroundSync.
  ///
  /// In en, this message translates to:
  /// **'Finishing background sync…'**
  String get finishingBackgroundSync;

  /// G18: a CSV row the import refuses (nothing is imported); problem is technical text
  ///
  /// In en, this message translates to:
  /// **'Row {row}: {problem}'**
  String csvImportInvalidRow(int row, Object problem);

  /// G39 welcome: jump to the last page
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get welcomeSkip;

  /// G39 welcome: next page
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get welcomeNext;

  /// G39 welcome: previous page
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get welcomeBack;

  /// G39 "How it works": close
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get welcomeDone;

  /// G39 welcome: page indicator (screen readers)
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {count}'**
  String welcomePageOf(int page, int count);

  /// G39 welcome page 1 title
  ///
  /// In en, this message translates to:
  /// **'Share expenses, fairly'**
  String get welcomeIntroTitle;

  /// G39 welcome page 1 body
  ///
  /// In en, this message translates to:
  /// **'MoneyLedger keeps track of who paid what in a group — a trip, a shared flat, a dinner — and shows who owes whom, like Splitwise or Tricount. Split equally or unevenly, record payments, settle up.'**
  String get welcomeIntroBody;

  /// G39 welcome page 2 title
  ///
  /// In en, this message translates to:
  /// **'Free, open source, no server'**
  String get welcomeOpenTitle;

  /// G39 welcome page 2 body
  ///
  /// In en, this message translates to:
  /// **'MoneyLedger is free software (AGPL-3.0-or-later) — anyone can read its source code. There is no MoneyLedger server and no MoneyLedger account: your groups and expenses are stored only on your devices.'**
  String get welcomeOpenBody;

  /// G39 welcome: link to the public repository
  ///
  /// In en, this message translates to:
  /// **'View the source code'**
  String get welcomeSourceLink;

  /// G39 welcome page 3 title; also the login page link
  ///
  /// In en, this message translates to:
  /// **'What is Matrix?'**
  String get welcomeMatrixTitle;

  /// G39 welcome page 3 body
  ///
  /// In en, this message translates to:
  /// **'Matrix is an open, decentralized messaging network. Like with e-mail, you choose a provider (a \"homeserver\", e.g. matrix.org) and create a free account there. MoneyLedger uses your Matrix account as your identity and as an end-to-end-encrypted relay to the other members of your groups — that is why you sign in.'**
  String get welcomeMatrixBody;

  /// G39 welcome page 4 title
  ///
  /// In en, this message translates to:
  /// **'Who sees what'**
  String get welcomePrivacyTitle;

  /// G39 welcome page 4, point 1
  ///
  /// In en, this message translates to:
  /// **'The members of a group get that group\'s expenses and payments on their devices — end-to-end encrypted.'**
  String get welcomePrivacyMembers;

  /// G39 welcome page 4, point 2
  ///
  /// In en, this message translates to:
  /// **'Homeservers only relay encrypted messages: they see which accounts exchange them and when, never the content, and keep nothing once it is delivered.'**
  String get welcomePrivacyServer;

  /// G39 welcome page 4, point 3
  ///
  /// In en, this message translates to:
  /// **'Nothing else: no MoneyLedger server, no tracking, no ads.'**
  String get welcomePrivacyNothingElse;

  /// G39 welcome: choices page title
  ///
  /// In en, this message translates to:
  /// **'How do you want to start?'**
  String get welcomeStartTitle;

  /// G39 welcome: choices page body
  ///
  /// In en, this message translates to:
  /// **'With a Matrix account you can share groups with others and sync your devices. Without one, everything stays on this device.'**
  String get welcomeStartBody;

  /// G39 welcome choice
  ///
  /// In en, this message translates to:
  /// **'Sign in with Matrix'**
  String get welcomeSignIn;

  /// G39 welcome choice
  ///
  /// In en, this message translates to:
  /// **'Create a Matrix account'**
  String get welcomeCreateAccount;

  /// G39/G40 welcome choice + login page link + local setup title
  ///
  /// In en, this message translates to:
  /// **'Use without an account'**
  String get welcomeUseLocal;

  /// G39 welcome: hint under the local choice
  ///
  /// In en, this message translates to:
  /// **'You can connect a Matrix account later — your groups come along.'**
  String get welcomeUseLocalHint;

  /// G39: About tile + title of the welcome pages read again
  ///
  /// In en, this message translates to:
  /// **'How MoneyLedger works'**
  String get howItWorksTitle;

  /// G40 local setup point
  ///
  /// In en, this message translates to:
  /// **'Your groups and expenses stay on this device only — nothing is sent anywhere.'**
  String get localSetupStaysHere;

  /// G40 local setup point
  ///
  /// In en, this message translates to:
  /// **'Add the other people by name.'**
  String get localSetupPeople;

  /// G40 local setup point
  ///
  /// In en, this message translates to:
  /// **'Back up regularly: if this device is lost or reset, the data is gone.'**
  String get localSetupBackup;

  /// G40 local setup point
  ///
  /// In en, this message translates to:
  /// **'You can connect a Matrix account later to share your groups.'**
  String get localSetupConnectLater;

  /// G40 local setup: the local ledger was adopted into an account earlier
  ///
  /// In en, this message translates to:
  /// **'Your earlier local groups were moved into {account} when you connected it — sign in with that account to see them. Local mode starts with an empty ledger.'**
  String localSetupAdoptedNotice(Object account);

  /// G40 local setup: name field
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get localSetupNameLabel;

  /// G40 local setup: name helper
  ///
  /// In en, this message translates to:
  /// **'How you appear in your groups'**
  String get localSetupNameHelper;

  /// G40: name required (local setup, add person in local mode)
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get localSetupNameRequired;

  /// G40 local setup: start button
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get localSetupStart;

  /// G40: groups app bar indicator
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get localModeChip;

  /// G40: explanation sheet / settings section title
  ///
  /// In en, this message translates to:
  /// **'Local mode'**
  String get localModeSheetTitle;

  /// G40 explanation sheet
  ///
  /// In en, this message translates to:
  /// **'You are using MoneyLedger without an account. Nothing leaves this device: nothing is synced, and the other people are only names in your groups.'**
  String get localModeSheetBody;

  /// G40 explanation sheet
  ///
  /// In en, this message translates to:
  /// **'Back up regularly (Settings → Back up all groups) — nobody else has a copy.'**
  String get localModeBackupHint;

  /// G40 explanation sheet
  ///
  /// In en, this message translates to:
  /// **'Connect a Matrix account to share groups with others and sync your devices. Your local groups move into that account.'**
  String get localModeConnectHint;

  /// G40 settings section subtitle
  ///
  /// In en, this message translates to:
  /// **'No account — everything stays on this device.'**
  String get localModeSettingsBody;

  /// G40 settings: the local profile name
  ///
  /// In en, this message translates to:
  /// **'Your name: {name}'**
  String localProfileName(Object name);

  /// G40 settings: name tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Used for new groups — rename yourself inside a group on its members page'**
  String get localProfileNameHint;

  /// G40: start the upgrade from local mode
  ///
  /// In en, this message translates to:
  /// **'Connect a Matrix account'**
  String get connectMatrixAccount;

  /// G40 settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Share your groups and sync your devices — your local data moves into the account'**
  String get connectMatrixAccountBody;

  /// G40: login page subtitle while connecting
  ///
  /// In en, this message translates to:
  /// **'Sign in — your local groups then move into this Matrix account'**
  String get connectSignInSubtitle;

  /// G40 settings: leave local mode
  ///
  /// In en, this message translates to:
  /// **'Delete local data'**
  String get deleteLocalData;

  /// G40 settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Removes all groups from this device and ends local mode'**
  String get deleteLocalDataBody;

  /// G40 confirmation title
  ///
  /// In en, this message translates to:
  /// **'Delete all local data?'**
  String get deleteLocalDataConfirmTitle;

  /// G40 confirmation body
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Local mode ends.} =1{The group and all its expenses and payments are deleted from this device.} other{All {count} groups with their expenses and payments are deleted from this device.}} There is no other copy unless you saved a backup. This can\'t be undone.'**
  String deleteLocalDataConfirmBody(int count);

  /// G40 confirmation button
  ///
  /// In en, this message translates to:
  /// **'Delete everything'**
  String get deleteLocalDataConfirmAction;

  /// G40 members page: own participant in local mode
  ///
  /// In en, this message translates to:
  /// **'You (on this device)'**
  String get localModeYouSubtitle;

  /// G40 members page hint
  ///
  /// In en, this message translates to:
  /// **'Local mode: people are added by name. Connect a Matrix account (Settings) to invite them.'**
  String get localModeMembersHint;

  /// G40 groups page banner after connecting
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Your local group now belongs to {account}.} other{Your {count} local groups now belong to {account}.}} You can invite members by their Matrix ID.'**
  String localAdoptedBanner(int count, Object account);

  /// Onboarding (after login / local start) title
  ///
  /// In en, this message translates to:
  /// **'You\'re all set'**
  String get onboardingReadyTitle;

  /// Onboarding subtitle (Matrix)
  ///
  /// In en, this message translates to:
  /// **'A few things worth knowing now that you are signed in.'**
  String get onboardingReadyBody;

  /// Onboarding subtitle (local mode)
  ///
  /// In en, this message translates to:
  /// **'A few things worth knowing about local mode.'**
  String get onboardingReadyLocalBody;

  /// Onboarding card (Matrix)
  ///
  /// In en, this message translates to:
  /// **'Syncs while you are away'**
  String get onboardingBackgroundTitle;

  /// Onboarding card (Matrix)
  ///
  /// In en, this message translates to:
  /// **'Members\' devices exchange changes while the app runs — on Android also about every 15 minutes in the background (Settings).'**
  String get onboardingBackgroundBody;

  /// Onboarding card (local mode)
  ///
  /// In en, this message translates to:
  /// **'Everything stays on this device'**
  String get onboardingLocalOnlyTitle;

  /// Onboarding card (local mode)
  ///
  /// In en, this message translates to:
  /// **'No account, no sync: create groups and add the other people by name. The \"Local only\" chip on the groups page explains it again.'**
  String get onboardingLocalOnlyBody;

  /// Onboarding card (local mode)
  ///
  /// In en, this message translates to:
  /// **'Nobody else has a copy of your ledger. Save a backup now and then (Settings → Back up all groups) and keep it somewhere safe.'**
  String get onboardingBackupLocalBody;

  /// Onboarding card (local mode)
  ///
  /// In en, this message translates to:
  /// **'Share later'**
  String get onboardingConnectLaterTitle;

  /// Onboarding card (local mode)
  ///
  /// In en, this message translates to:
  /// **'Settings → Connect a Matrix account moves your groups into an account, so you can invite others and sync your devices.'**
  String get onboardingConnectLaterBody;

  /// Privacy policy section title (G40)
  ///
  /// In en, this message translates to:
  /// **'Local mode (without an account)'**
  String get privacyLocalTitle;

  /// Privacy policy section body (G40)
  ///
  /// In en, this message translates to:
  /// **'If you use MoneyLedger without a Matrix account, nothing leaves your device: the app contacts no server and nothing is synced (the web version is only loaded from the site that hosts it). Links you tap, e.g. to the source code, open in your browser. Your name, groups, expenses and payments are stored only in a local database on this device, plus a small preferences file (whether you saw the welcome, your local profile name). Deleting local data in the settings, or uninstalling the app, removes them. If you later connect a Matrix account, the local data moves into that account and from then on the sections above apply.'**
  String get privacyLocalBody;

  /// Category selector entry / value for an expense without a category (G47)
  ///
  /// In en, this message translates to:
  /// **'No category'**
  String get categoryNone;

  /// Last entry of the category selector: create a custom category (G47)
  ///
  /// In en, this message translates to:
  /// **'New category…'**
  String get newCategoryEntry;

  /// Title of the dialog creating a custom category (G47)
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get newCategoryTitle;

  /// Title of the dialog renaming a custom category (G47)
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get editCategoryTitle;

  /// Name field of the custom category dialog (G47)
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get categoryNameLabel;

  /// Icon picker label of the custom category dialog (G47)
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get categoryIconLabel;

  /// Validation error: custom category name too long (G47)
  ///
  /// In en, this message translates to:
  /// **'At most {max} characters'**
  String categoryNameTooLong(int max);

  /// Validation error: duplicate custom category name (G47)
  ///
  /// In en, this message translates to:
  /// **'This group already has a category with this name'**
  String get categoryNameTaken;

  /// Group menu item + page title: manage the group's custom categories (G47)
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get manageCategories;

  /// Explanation on the group categories page (G47)
  ///
  /// In en, this message translates to:
  /// **'Your own categories are shared with everyone in this group. Hidden ones aren\'t offered for new expenses but still label older ones.'**
  String get customCategoriesHint;

  /// Empty state of the group categories page (G47)
  ///
  /// In en, this message translates to:
  /// **'No categories of your own yet.'**
  String get noCustomCategories;

  /// Tooltip: hide a custom category (G47)
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideCategory;

  /// Tooltip: un-hide a custom category (G47)
  ///
  /// In en, this message translates to:
  /// **'Show again'**
  String get showCategory;

  /// Subtitle of a hidden custom category (G47)
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get categoryHidden;

  /// Shown when the custom category limit is reached (G47)
  ///
  /// In en, this message translates to:
  /// **'A group can have at most {max} categories of its own.'**
  String categoryLimitReached(int max);

  /// Section header in the category selector (G47)
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get builtInCategories;

  /// Section header in the category selector: the group's own categories (G47)
  ///
  /// In en, this message translates to:
  /// **'This group'**
  String get groupCategories;

  /// Settings tile + page title: on-device snapshots (G48)
  ///
  /// In en, this message translates to:
  /// **'Restore points'**
  String get restorePointsTitle;

  /// Settings tile subtitle (G48)
  ///
  /// In en, this message translates to:
  /// **'Automatic copies on this device, undo changes'**
  String get restorePointsTileBody;

  /// Restore points page intro (G48)
  ///
  /// In en, this message translates to:
  /// **'Once a day, when something changed, MoneyLedger keeps a copy of all your groups on this device — the last 7 days plus 4 older weeks. These copies never leave this device.'**
  String get restorePointsIntro;

  /// Restore points page: what a restore does vs. a group reset (G48)
  ///
  /// In en, this message translates to:
  /// **'Restoring brings back groups and entries that are missing here (e.g. a deleted group). To undo changes inside a group, open the group → ⋮ → Reset to an earlier state.'**
  String get restorePointsHowItWorks;

  /// Restore points page: none yet (G48)
  ///
  /// In en, this message translates to:
  /// **'No restore points yet. One is made once a day when something changed.'**
  String get restorePointsEmpty;

  /// Restore points page on web (G48)
  ///
  /// In en, this message translates to:
  /// **'The browser version keeps no automatic copies. You can still reset a group to an earlier state (group → ⋮) and back up to a file.'**
  String get restorePointsWebUnsupported;

  /// Restore point subtitle part (G48)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 group} other{{count} groups}}'**
  String restorePointGroups(int count);

  /// Restore point subtitle part (G48)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry} other{{count} entries}}'**
  String restorePointEntries(int count);

  /// Button on a restore point (G48)
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restorePointRestore;

  /// Error on the restore points page (G48)
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the restore points: {error}'**
  String restorePointsLoadFailed(String error);

  /// Group ⋮ menu item (G48)
  ///
  /// In en, this message translates to:
  /// **'Reset to an earlier state…'**
  String get groupResetMenu;

  /// Reset page title (G48)
  ///
  /// In en, this message translates to:
  /// **'Reset group'**
  String get groupResetTitle;

  /// Reset page intro (G48)
  ///
  /// In en, this message translates to:
  /// **'Pick a change to undo it and everything after it. Expenses, payments and the group settings go back to how they looked on this device before it. Members stay as they are. Everyone in the group gets the result as a normal change — and you can undo a reset the same way.'**
  String get groupResetIntro;

  /// Reset page intro in local mode (G48)
  ///
  /// In en, this message translates to:
  /// **'Pick a change to undo it and everything after it. Expenses, payments and the group settings go back to how they looked before it. Members stay as they are. You can undo a reset the same way.'**
  String get groupResetLocalIntro;

  /// Reset page footer (G48)
  ///
  /// In en, this message translates to:
  /// **'Changes are kept on this device for 90 days.'**
  String get groupResetRetention;

  /// Reset page: no resettable change (G48)
  ///
  /// In en, this message translates to:
  /// **'Nothing to go back to yet — changes show up here as they happen.'**
  String get groupResetEmpty;

  /// Reset page for a read-only group (G48)
  ///
  /// In en, this message translates to:
  /// **'You were removed from this group, so it can\'t be reset.'**
  String get groupResetReadOnly;

  /// Change batch part (G48)
  ///
  /// In en, this message translates to:
  /// **'{count} added'**
  String changeAdded(int count);

  /// Change batch part (G48)
  ///
  /// In en, this message translates to:
  /// **'{count} edited'**
  String changeEdited(int count);

  /// Change batch part (G48)
  ///
  /// In en, this message translates to:
  /// **'{count} deleted'**
  String changeDeleted(int count);

  /// Change batch part (G48)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 group or member change} other{{count} group or member changes}}'**
  String changeOther(int count);

  /// Change batch: written on this device (G48)
  ///
  /// In en, this message translates to:
  /// **'by you'**
  String get changeByYou;

  /// Change batch: who changed it (G48)
  ///
  /// In en, this message translates to:
  /// **'by {names}'**
  String changeBy(String names);

  /// Button on a change batch (G48)
  ///
  /// In en, this message translates to:
  /// **'Undo from here'**
  String get changeUndoFromHere;

  /// Marker on the oldest change batch (G48)
  ///
  /// In en, this message translates to:
  /// **'Earliest state on this device'**
  String get changeEarliest;

  /// Reset preview dialog title (G48)
  ///
  /// In en, this message translates to:
  /// **'Go back to before {time}?'**
  String resetPreviewTitle(String time);

  /// Reset preview line (G48)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry comes back} other{{count} entries come back}}'**
  String resetPreviewRestored(int count);

  /// Reset preview line (G48)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change is undone} other{{count} changes are undone}}'**
  String resetPreviewReverted(int count);

  /// Reset preview line (G48)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry is removed} other{{count} entries are removed}}'**
  String resetPreviewRemoved(int count);

  /// Reset preview line (G48)
  ///
  /// In en, this message translates to:
  /// **'Group name, currency and categories go back too.'**
  String get resetPreviewMeta;

  /// Reset preview line (G48)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 earlier version can\'t be used and stays as it is.} other{{count} earlier versions can\'t be used and stay as they are.}}'**
  String resetPreviewSkipped(int count);

  /// Reset preview: no change (G48)
  ///
  /// In en, this message translates to:
  /// **'Nothing to change — the group already looks like that.'**
  String get resetPreviewNothing;

  /// Reset preview note (G48)
  ///
  /// In en, this message translates to:
  /// **'Everyone in the group gets these changes.'**
  String get resetPreviewShared;

  /// Reset preview: list truncated (G48)
  ///
  /// In en, this message translates to:
  /// **'…and {count} more'**
  String resetPreviewMore(int count);

  /// Reset preview item label (G48)
  ///
  /// In en, this message translates to:
  /// **'comes back'**
  String get resetEffectRestored;

  /// Reset preview item label (G48)
  ///
  /// In en, this message translates to:
  /// **'changed back'**
  String get resetEffectReverted;

  /// Reset preview item label (G48)
  ///
  /// In en, this message translates to:
  /// **'removed'**
  String get resetEffectRemoved;

  /// Reset preview confirm button (G48)
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetConfirm;

  /// Snackbar after a reset (G48)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Group reset (1 change)} other{Group reset ({count} changes)}}'**
  String resetDone(int count);

  /// Privacy policy section title (G48)
  ///
  /// In en, this message translates to:
  /// **'Restore points on this device'**
  String get privacyRestorePointsTitle;

  /// Privacy policy section body (G48)
  ///
  /// In en, this message translates to:
  /// **'To let you undo mistakes, MoneyLedger keeps earlier versions of your groups\' entries on this device for 90 days, and on Android once a day (when something changed) a copy of all your groups in the app\'s private storage — the last 7 days plus 4 older weeks. These versions and copies are never sent anywhere, are not part of any backup file, and are excluded from Android\'s backups like all app data. Leaving or deleting a group removes its earlier versions at once; the daily copies still contain it until they rotate out (after about five weeks), so that a group deleted by mistake can be restored. Deleting local data, or uninstalling the app, removes all of them.'**
  String get privacyRestorePointsBody;

  /// G49 expense date field label
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get expenseDateLabel;

  /// G49 expense date field: date picker title
  ///
  /// In en, this message translates to:
  /// **'When did it happen?'**
  String get expenseDatePickerHelp;

  /// G56: copy a value (e.g. a Matrix ID) to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// G56: snackbar after copying to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copiedToClipboard;

  /// G56: settings sheet 'Devices & security' tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Your logins and emoji verification'**
  String get devicesSettingsBody;

  /// G56: card above the ledger when I'm the only member but there are already expenses
  ///
  /// In en, this message translates to:
  /// **'It\'s just you in this group so far.'**
  String get addPeopleHint;

  /// G56: tooltip of a card's close button
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// G56: leaving a changed expense form
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesTitle;

  /// G56: leaving a changed expense form — body
  ///
  /// In en, this message translates to:
  /// **'What you entered for this expense will be lost.'**
  String get discardChangesBody;

  /// G56: discard-changes dialog: leave without saving
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// G56: discard-changes dialog: stay on the form
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
