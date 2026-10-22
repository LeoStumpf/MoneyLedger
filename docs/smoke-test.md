# Manual smoke test

A repeatable manual checklist for every user flow. Unit/widget/integration tests
run against fakes (`flutter test`); this list covers what only a real build on a
real homeserver can prove (E2EE to-device delivery, deep links, file picker,
release signing, …).

**Setup.** Release build: `flutter build apk --release`, install with
`adb -s <device> install -r build/app/outputs/flutter-apk/app-release.apk`
(`-r` keeps the app data/session). Two test accounts on matrix.org
(`~/.config/moneyledger-test/accounts.env`): **A** on device 1, **B** on device 2.
UI driving from a shell: `adb shell input …` + `adb shell uiautomator dump`.

**How each item can be tested** (column *How*):

| Tag | Meaning |
|-----|---------|
| `emu` | one emulator is enough |
| `phone` | needs a physical device (file picker, real browser, …) — an emulator usually works too |
| `2dev` | needs two signed-in devices (A + B, or two devices of A) |
| `Leo` | needs Leo personally (personal account, SAS emoji compare on two screens, creating a real account) |

Expected results are in *italics*.

## 1. Install, first start, onboarding

| # | Step → expected | How |
|---|-----------------|-----|
| 1.1 | Fresh install, launch → *welcome (G39, G54): 4 pages (what it is · free/open source/no server · share a group with a link · want more security? Matrix + "Why Matrix?") + "How do you want to start?" with Start without an account / Join with an invite link / Secure mode: Sign in / Create a Matrix account*; Sign in → *login screen, homeserver prefilled `matrix.org`, no crash*; relaunch → *no welcome again*. **G79:** on the welcome (before any choice) `adb -s <serial> shell run-as io.github.leostumpf.moneyledger ls files/` (debug build; app support dir) shows **no** `money_ledger_matrix.sqlite`; it appears only after *Sign in* / *Create account* | emu |
| 1.2 | Launcher label + icon → *app name and icon shown (currently `money_ledger` + Flutter default, see G12)* | emu |
| 1.3 | First login of an account on this device → *onboarding "You're all set" (invite / background sync / keep a copy — no repetition of the welcome) shown once; "Get started" → Groups* | emu |
| 1.4 | Kill + relaunch → *goes straight to Groups (session restored, no onboarding, no hang on a slow sync)* | emu |
| 1.5 | Airplane mode, relaunch → *Groups and all local data shown offline* | emu |

| 1.6 | About → *How MoneyLedger works* and login → *What is Matrix?* → *the welcome pages again, no choices, Done goes back* (G39); device in German → *German texts* | emu |
| 1.7 | Welcome → *Start without an account* → name → *local onboarding (No account needed / Invite with a link / Keep a copy) → Groups with a "No account" chip and the settings gear only; Settings has no Sync / Advanced (Matrix) / Sign out* (G40, G65, G75) | emu |
| 1.8 | Local mode: create a group, *Add person* (name only — no Matrix ID field, no invite icon), expenses + a payment, balance, Back up all groups → *all works offline; no sync cloud; members page "You (on this device)"; logcat: no Matrix client / `[sync]` lines* | emu |
| 1.9 | "No account" chip → *sheet: unshared groups never leave this device, back up, connect an account (link groups keep their link), Why Matrix?* | emu |
| 1.10 | Settings → *Connect a Matrix account* → login (close = cancel back to local) → sign in → *groups page banner "Your N local groups now belong to @…"; group members: you are the claimed member (MXID shown); logcat `[local] adopted N local group(s) … rows signed`* | emu |
| 1.11 | After 1.10, another device of the same account → *the adopted group arrives (own-device digest → resync) with all entries; logcat there: no `[g6] refused`* | 2dev |
| 1.12 | Signed out afterwards → *Start without an account* again → *setup page says the earlier local groups moved into @…; local mode starts empty*; Settings → *Delete local data* → confirm → *login page* | emu |
| 1.13 | (G41) Local mode: a group with a person + an expense → *Back up all groups* (unencrypted) → Settings → *Delete local data* → confirm → *login page; `run-as`/root `ls …/app_flutter/` shows **no** `money_ledger_local.sqlite` (nor `-wal`/`-shm`/`-journal`)* | emu |
| 1.14 | (G41) After 1.13: sign in with a Matrix account → Settings → *Restore from backup* → the local backup → *preview shows the takeover note "made without a Matrix account … moves its groups into @…" (no "other account" warning)* → Restore → *logcat `[backup] adopted N local-mode group(s) into @… (M rows signed)`; the expense shows "Added by you"; members: you are the claimed member* | emu |
| 1.15 | (G41) After 1.14, another device of the same account → *the restored group arrives with all entries; logcat there: no `refused` lines* | 2dev |
| 1.16 | (G41) A Matrix account's backup restored **in local mode** → *preview note "belongs to the Matrix account @… — you take that account's place"; groups appear, you are "me" in them; nothing sent* — **not yet run on a device** (unit-tested: `test/features/local_backup_restore_test.dart`) | emu |

## 2. Login, registration, account switch

| # | Step → expected | How |
|---|-----------------|-----|
| 2.1 | Password login (homeserver, username, password) → *Groups (or onboarding)* | emu |
| 2.2 | Wrong password → *error shown, stays on login, no crash* | emu |
| 2.3 | Homeserver with SSO (matrix.org) → *"Continue with …" SSO button appears after the flow lookup* | emu |
| 2.4 | Tap an SSO button → *system browser opens the homeserver SSO page* | emu |
| 2.5 | Complete SSO in the browser → *`moneyledger://sso-callback?loginToken=…` returns to the app, signed in* | Leo |
| 2.6 | Signed out: `adb shell am start -a android.intent.action.VIEW -d "moneyledger://sso-callback?loginToken=invalid" io.github.leostumpf.moneyledger` → *"SSO login failed: …" snackbar, stays on login, no crash* | emu |
| 2.7 | Login → "New here? Create an account" → fill dummy username/password (no account is created on matrix.org: it disabled client registration / needs captcha etc.) → Create account → *"Register on the web" card ("signing up on its own website" for matrix.org, or the required UIA stages) + "Open homeserver website"* | emu |
| 2.8 | "Open homeserver website" → *browser opens the homeserver* | emu |
| 2.9 | Registration on a homeserver with an open `m.login.dummy` flow → *account created, signed in* | Leo |
| 2.10 | Settings → Account → Sign out (confirm) → *back on login; the device disappears from the account's device list; local data stays on disk (per-account DB)* | emu |
| 2.11 | Sign in as a different account on the same device → *onboarding again (per-account flag), then only that account's groups (recovered from its other device), "You" = that account*; sign back in as the first → *its groups are back* | 2dev |

## 3. Groups

| # | Step → expected | How |
|---|-----------------|-----|
| 3.1 | "New group" → name + currency → Create → *back on Groups, new group listed* | emu |
| 3.2 | ⋮ → Group settings (or tap the title) → Name & currency: rename + change default currency → *title/list updated; peer shows new name* | 2dev |
| 3.3 | New expense after currency change → *uses the new currency (the form has no per-expense currency picker — the group default is used)* | emu |
| 3.4 | Group settings → Leave or delete → Leave group (shared group, you are a member) → *warning "You are still owed …" + "Back up all groups first"; group disappears; peer sees you under "No longer in the group"* | 2dev |
| 3.5 | Re-add the leaver from the peer → *group comes back on the leaver's device with full history* | 2dev |
| 3.6 | Group settings → Leave or delete → Delete group (solo/local-only group, or every other claimed member left) → *balance warning; "Deleted …" snackbar; group gone from this device* | emu |
| 3.7 | Removed by a peer → *banner "You were removed from this group", history read-only, "Delete from this device"* | 2dev |
| 3.8 | ⋮ → Archive group → *back on Groups; group in the collapsed "Archived (N)" section; snackbar Undo works; totals unchanged* (G16) | emu |
| 3.9 | Peer adds an expense to the archived group → *group is back among the active groups by itself* (G16) | 2dev |
| 3.10 | Open an archived group → *"archived on this device" banner*; ⋮ / banner / group settings → Unarchive → *back in the list* (G16) | emu |
| 3.11 | (G65, DE, 360 dp) Group ⋮ → *only Person hinzufügen / Archivieren / Gruppeneinstellungen*; title tap → *Gruppeneinstellungen with Gruppe / Personen / Daten / Auf diesem Gerät / Verlassen oder löschen (red, last)*; removed group → *Name & Währung + Zurücksetzen greyed, "Gruppe löschen"*; Groups app bar → *only the gear (+ "Kein Konto" chip)*; Settings page → *Konto / Synchronisierung & Geräte / Sichern & Wiederherstellen / Daten / Info*, back-up / restore dialogs + snackbars visible on the page | phone |

## 4. Members

| # | Step → expected | How |
|---|-----------------|-----|
| 4.1 | Members → "Invite by Matrix ID" with B's MXID → *if local people exist: "Who is B in this group?" (a local person or "A new participant"); B listed (Matrix) as that participant; B's device receives the group (bootstrap) and is a member at once* (G18) | 2dev |
| 4.2 | Invite an invalid ID (`bob`) → *"Invalid Matrix ID"* | emu |
| 4.3 | "Add person" (name only) → *listed as "Local"; usable as payer / in splits* | emu |
| 4.4 | Local person → ⋮ Link Matrix account (MXID) → *shows the MXID; that account now receives the group* | 2dev |
| 4.5 | A group this device holds without being a participant (e.g. CSV import) → *banner "Which participant are you?" → Choose: a local person or "I'm someone new" + name (local; peers only accept it from an active member — G18)* | emu |
| 4.6 | ⋮ Rename / Detach Matrix account → *name changes everywhere; history keeps the participant* | emu |
| 4.7 | ⋮ Remove from group → *warns with the open balance (+ "Settle up first") if any; moves to "No longer in the group" (greyed, "Re-add"); expenses still show the name* | emu |
| 4.8 | "Re-add" a former member (claimed **or** local) → *same participant reactivated (same name/history), no duplicate; peer sees it* | 2dev |

## 5. Expenses

| # | Step → expected | How |
|---|-----------------|-----|
| 5.1 | Add expense, **Equal** split, untick one person → *only ticked people in the split; shares sum to the total exactly (e.g. 10.00/3 → 3.34/3.33/3.33)* | emu |
| 5.2 | **Exact** amounts → *status shows remaining; save only when it sums to the total* | emu |
| 5.3 | **Shares** (e.g. 2:1) → *preview proportional, sums exactly* | emu |
| 5.4 | **%** (e.g. 70/30) → *preview proportional; must sum to 100 %* | emu |
| 5.5 | Edit an expense (tap) → *form prefilled (equal → Equal, else Exact); save updates list + peer* | 2dev |
| 5.6 | ⋮ Delete → confirm → *gone here and on the peer (tombstone)* | 2dev |
| 5.7 | Keyboard open on the form → *Add/Save button reachable (known: covered, G17)* | emu |
| 5.8 | Type "Pizza" → *Category field shows Food & drink*; open it, pick another → *typing no longer changes it*; pick *No category* → *none* (G16, selector since G47) | emu |
| 5.9 | Add a category + note → *category icon in the list, note icon after the title; peer shows the same icon + note (DE labels on a German device)* (G16) | 2dev |
| 5.10 | 🔍 in the group app bar → type part of a description / note / payer → *list filtered, "N entries"*; category chips + "Involving me" narrow it; nothing found → *"Clear filters"* (G16) | emu |
| 5.11 | Amount field: German device, type `1.234` → *preview "= 1.234,00 €" (thousands)*; English device `1.234` → *"= €1.23"*; `0` / `-5` → *Add disabled, no preview* (G18) | 2dev |
| 5.12 | Start the app while a background round runs (trigger the job, open the app at once) → *"Finishing background sync…" briefly, then the app; logcat `[bg-gate] background round finished`* (G18) | phone |
| 5.13 | Category field → *New category…* → name "Dog" + an icon → *selected on the form*; the peer's selector offers "Dog" too (G47) | 2dev |
| 5.14 | Group settings → Categories → rename "Dog", hide it → *peer shows the new name; hidden: not offered for new expenses, old expenses keep the label* (G47) | 2dev |
| 5.15 | Add expense → *Date shows "Today"*; tap *Yesterday* or the field → pick a day last week → Add → *listed under that day on both devices*; edit it → *the date is prefilled* (G49) | 2dev |
| 5.16 | Record payment → *Date shows "Today"*; tap *Yesterday* → Record → *listed under yesterday on both devices* (G60) | 2dev |
| 5.17 | (G75) Row ⋮ → *Duplicate* → *add form with the same description / amount / currency / payer / split / category / note, Date "Today"; back without Add → nothing new*; Add → *a second expense under today, on the peer too*; edit form → copy icon → *same, the edit page is replaced* | 2dev |
| 5.18 | (G75, G79) Amount fields offer the **decimal keypad** only and advertise no calculator (no hint / helper about `+ - * /` — Gboard's decimal keypad has only `-`). A **pasted** expression is still accepted: paste `12,50+8` (German) → *preview "= 20,50 €", Add saves 20,50*; `12+` → *Add disabled*; same in the payment dialog | phone |
| 5.19 | (G77) Add expense 30 € → *Split by items…* → Pizza 12 (only Anna), Pasta 9 (only Bob), Wine 6 (everyone) → *"Rest (tax, tip, not itemized): 3,00 €", per person 15,56 / 12,22 / 2,22*; switch the rest to *Equally* → *15 / 12 / 3*; *Use this split* → *Amounts mode, "Adds up to the total"*; Add → *peer shows the same split*. Items over the amount → *"… too much"* + *Set total to the sum* sets the form's amount. German UI + 200 % font: item cards, chips and the rest choice don't overflow; back on the editor page keeps the items | phone |
| 5.20 | (G78, Android only) Add expense → *Add receipt photo* → *Take photo* → the **system camera app** opens (no permission prompt from MoneyLedger), shoot a receipt → *thumbnail + "Only on this device — not shared with the group, not in backups."*; Add → *the ledger row shows the photo icon*; the peer gets the expense **without** any photo. Reopen → tap the thumbnail → full screen, pinch-zoom, ✕ back. *Replace* → *Choose from gallery* → the **system photo picker** (Android 13+; no storage permission) → Save → *"Receipt photo saved"*, no new sync version (peer's "last edited" unchanged). *Remove* → Save → *"Receipt photo removed"*. File check (debug build): `adb -s <serial> shell run-as io.github.leostumpf.moneyledger ls -l files/receipts/*/` → `<expense id>.jpg`, ~200–400 KB, long edge ≤ 1600 px; `ls cache/` holds no leftover camera shot. Delete the expense → *Undo* keeps the photo; delete again, force-stop + restart → the file is gone. Delete a group with a photo → its file is gone at once. Not offered on the web build. German UI: *Belegfoto* section | phone |
| 5.21 | (G74) Settings → *Payment details*: a mistyped IBAN (change the last digit) → *"This isn't a valid IBAN"*; IBAN without a name → *name needed*; `https://paypal.me/<name>` pasted → accepted. Save → tile shows *"IBAN …1234 · paypal.me/<name>"*. Balance page of a group where someone owes you in **EUR** → QR icon on that row (not on rows between others) → sheet: GiroCode; scan with a **banking app** (e.g. Sparkasse / ING / N26 "Foto-Überweisung" / GiroCode) → *name, IBAN, amount and the group name prefilled*. *PayPal* tab → scan with the camera → PayPal opens *with the amount*; *Share link* → system sheet. A **CHF** debt → no GiroCode, IBAN as text + *Copy IBAN*. Peer device: **nothing** of it arrives (members / digests unchanged). German UI, 360 dp + 200 % font: sheet scrolls, nothing overflows | phone |
| 5.22 | (G76) Add expense 90 € → *Paid by* → *Several people…* → one amount per person: Anna 60 → *"30,00 € left"*, ⊕ on Bob → *"Adds up to the total"*; *Add* stays disabled while it doesn't add up. Ledger row → *"Paid by Anna and Bob"* (*"Paid by you and Bob"* when you are one of them; 3+ → *"Paid by 3 people"*); balance page → Anna gets back 30, Carl owes 30 (equal split of three); **peer device: same row, same balances**, edit there → the payers are prefilled. Edit → pick one person again → saved as a normal single payer. CSV export → empty *Paid By* + *Paid: <name>* columns; re-import → same. German UI, 360 dp + 200 % font: payer rows don't overflow | 2dev |

## 6. Settlements & balances

| # | Step → expected | How |
|---|-----------------|-----|
| 6.1 | Balance → tap **your own** debt row (only the debtor can) → Record settlement → Confirm → *debt cleared here and on the peer* | 2dev |
| 6.2 | Expense list → *settlement shown (handshake icon, "A paid B", date)* | emu |
| 6.3 | Settlement ⋮ Delete → *gone; balance restored; peer too* | 2dev |
| 6.4 | Edit group → default currency USD → add an expense → *balance page shows separate EUR and USD debts, no conversion* (then delete it + switch back) | emu |
| 6.5 | Everything settled → *"All settled up!"* | emu |
| 6.6 | Balance → ⓘ next to "Suggested payments" → *"Simplified debts" explanation*; multi-currency group → *"settled separately per currency" note* (G16) | emu |
| 6.7 | (G73) Group with EUR + CHF expenses → balance page → *Set exchange rates* → *Add rate* → CHF → dialog *1 CHF in EUR*: the source line names api.frankfurter.dev; **nothing is requested before the tap** (debug logcat / browser network tab); *Fetch current rate* → *rate filled in, "Reference rate of …"*; Save → turn on *Settle up in EUR* → balance page: *one EUR section + "Settled in EUR …" note*; the peer shows the same rates (group settings tile) and the same EUR debts. Remove the rate → *both back to per-currency*. Offline: *Fetch* → friendly network error inline. German, 360 dp: *"1 CHF = 1,0797 EUR"*, dialog fits | 2dev |

## 7. Sync

| # | Step → expected | How |
|---|-----------------|-----|
| 7.1 | A adds/edits/deletes → *B shows it within seconds (app in foreground)* | 2dev |
| 7.2 | Sync icon: all peers acked → *filled cloud "Synced with all members"*; pending → *outlined cloud "Waiting for …"* | 2dev |
| 7.3 | Member without any logged-in device → *outlined cloud, tooltip "… has no active device — will sync when they sign in"* | 2dev |
| 7.4 | Repeated send failures (e.g. airplane mode + edits) → *red cloud_off; sheet with last error + "Retry now"* | emu |
| 7.5 | B offline (airplane), A edits, B online again → *B catches up (to-device queue or next digest)* | 2dev |
| 7.6 | B kills the app, A adds; B relaunches → *expense arrives right after start (startup buffer, G24)* | 2dev |
| 7.7 | New-device recovery: sign A in on a fresh device → *A's groups + history arrive via `resync_request{all}` from A's other device* | 2dev |
| 7.8 | Leave on one of A's devices → *group also leaves A's other devices* | 2dev |
| 7.9 | A adds an expense with B's app in the foreground → *A's cloud turns "Synced" within ~6 s (B's fast ack, G36)* | 2dev |
| 7.10 | B (emulator): `svc wifi disable; svc data disable`, wait 1–3 min, enable one of them (network switch); A adds → *arrives on B without restarting the app* (G36) | 2dev |
| 7.11 | Debug build only: Settings → "Run background sync now (debug)" → swipe the app away → *after ~15 s logcat shows a `[bg]` round*; release build → *no such entry* (G36) | emu |
| 7.12 | Update an install from before G45 (account also used in Element) → *logcat `[g45] cleared sync data of the previous sync filter` once (debug/profile builds only — release builds log nothing, G44); sync, invite, SAS still work; Element shows the device not as online / presence unchanged*; `GET /_matrix/client/v3/user/<mxid>/filter/<id>` (id from logcat/SDK store) → *the minimal filter (`rooms: []`)* (G45) | 2dev |

## 8. Backup (JSON) and CSV

| # | Step → expected | How |
|---|-----------------|-----|
| 8.1 | Group settings → Data → Export CSV → *system save dialog ("<group>.csv"); saved to Downloads; "Exported …" snackbar* | phone |
| 8.2 | Open the CSV in a sheet app → *one row per expense, then one per payment (Type "Payment"), decimal amounts, a share column per participant* | phone |
| 8.3 | Settings → Data → Import CSV (or the empty groups list's button) → pick the same file → *preview "Merges into your group …"; no duplicate expenses/payments/group (idempotent merge)* | phone |
| 8.4 | Import into a device that lacks the group → *group created with its participants (local by name)* | phone |
| 8.5 | Settings (gear) → *Backup & restore* tile → Back up all groups → *save dialog `moneyledger-backup-YYYY-MM-DD.json`; "Backup saved"; the page and the settings tile show "Last backup: <today>"* | phone |
| 8.6 | Settings → Backup & restore → Restore from backup → pick that file → *preview "No new groups … already on this device"; Restore → "Restored N groups", nothing duplicated* | phone |
| 8.7 | Solo group (no other Matrix member), no backup for 30 days → *"Back up your groups" card on the groups page; Later hides it for 30 days* | phone |
| 8.8 | Settings → Backup & restore → Back up all groups → passphrase dialog: type one → *confirm field + strength hint; mismatch disables Save*; matching → *"Encrypting…" (≈ 1 s), "Encrypted backup saved[: name]"; the file is a `moneyledger-backup-encrypted` wrapper (no readable names)* | emu |
| 8.9 | Restore that file → *"Encrypted backup" prompt*; wrong passphrase → *"Wrong passphrase — or the file was changed. Try again."*; right one → *preview incl. "Encrypted backup — unlocked…", "Everything … already on this device"; Restore = no-op* | emu |
| 8.10 | Group settings → Data → Back up this group → *file `moneyledger-backup-<group>-YYYY-MM-DD.json` with only that group; "Last backup" unchanged* | emu |
| 8.11 | Leave/Delete group dialog → "Back up all groups first" → *passphrase dialog over it; the result ("Backup saved …") shows inside the leave dialog* | emu |
| 8.12 | A second own device that is verified (or synced with this one in the last 30 days) → *no backup nudge for solo groups* | phone |
| 8.13 | (G48) Device B deletes two expenses and edits one in a shared group → on A: group settings → *Reset to an earlier state…* → newest entry "N deleted · by B" → *Undo from here* → *preview "2 entries come back · 1 change is undone"*; Reset → *"Group reset (3 changes)"*; on B the entries are back within seconds, "Last edited by A" | phone + emu |
| 8.14 | (G48, Android) App start on a day with changes → `files/snapshots/money_ledger_<hash>/YYYY-MM-DD.json` appears (`adb -s <serial> shell run-as io.github.leostumpf.moneyledger ls -R files/snapshots`); Settings → Backup & restore → *Show restore points* lists it ("1 group · N entries"); Restore → *the normal restore preview* (no change = "already on this device") | phone |
| 8.15 | (G48) Delete a solo group, then Settings → Backup & restore → Show restore points → yesterday's point → Restore → *the group is back* | emu |
| 8.16 | (G70, DE, 360 dp) Einstellungen → *Sichern & Wiederherstellen* (eine Kachel mit „Letzte Sicherung: …“) → *Seite mit „Was brauchst du?“ (4 Zeilen: Rückgängig / Gruppe zurücksetzen / Wiederherstellungspunkt / neues Handy → Sicherungsdatei; mit Matrix-Konto der Zusatz „Gruppen, die du mit anderen teilst …“), dann SICHERUNGSDATEI / WIEDERHERSTELLUNGSPUNKTE / ÄNDERUNGEN IN EINER GRUPPE RÜCKGÄNGIG MACHEN*; nothing cut off, texts readable | phone |
| 8.17 | (G70) Backup & restore → *Choose a group …* → *sheet "Which group?" sorted by name* → a group → *its "Reset to an earlier state" page*; a removed (read-only) group → *the reset page's read-only state*; local mode → *no "come back from the others" line*; web → *"Not available in the browser" instead of the restore points tile* | phone + web |
| 8.18 | (G70) Backup nudge card → *Back up now* still starts the export directly (passphrase dialog) | phone |

## 9. Devices & verification

| # | Step → expected | How |
|---|-----------------|-----|
| 9.1 | Settings → Advanced (Matrix) → Devices & security → *all of the account's devices listed (this one first) with verified status* | emu |
| 9.2 | "Verify" another own device → *emoji dialog on both; "They match" on both → "Device verified."* | Leo |
| 9.3 | Cancel mid-verification → *dialog closes, no crash, device stays unverified* | Leo |
| 9.4 | The other device shows "Verification request … Accept / Decline" on any screen → Accept → *same emoji dialog* | emu |
| 9.5 | Members → tap "N unverified devices" under a member (or ⋮ → Devices) → Verify their device; they accept → *emoji dialog on both; both "Device verified."; the member's device and ours show Verified on both sides* | emu |
| 9.6 | Settings → Advanced (Matrix) → "Only sync with verified devices" → *confirmation: three short sentences + "Learn more" (the details)* (G75); on → add an expense → *verified devices (own + peers) get it; a member with no verified device: members page red "Not reachable — no verified device", sync tooltip "X has no verified device …", they don't receive it* | emu |
| 9.7 | Signature details of a record from a device you haven't verified → *"You haven't verified this device."* | emu |
| 9.8 | German UI: the SAS emoji dialog → *names in German (Hund, Katze, …), English UI in English* (G36) | 2dev |

## 10. Release build

| # | Step → expected | How |
|---|-----------------|-----|
| 10.1 | `flutter build apk --release` → *succeeds; signed with the release keystore (`apksigner verify --print-certs`), not the debug key* | emu |
| 10.2 | `adb install -r` over the previous release → *upgrade keeps session and data* | emu |
| 10.3 | Permissions (`aapt dump permissions` / app info) → *INTERNET only (+ plugin-merged ones); no storage permission needed for export/import* | emu |
| 10.4 | Web: `flutter build web --release`, serve `build/web` → *login, E2EE init (vodozemac wasm), sync works* | emu |

## 11. Accessibility + form flow (G71)

Run on the Pixel during the G52 step 13 device pass.

| # | Step → expected | How |
|---|-----------------|-----|
| 11.1 | TalkBack on → groups page: swipe through → *"Overview" heading; "You are owed, €…" / "You owe, €…" as one phrase each; every icon button says what it does (settings, add); the archived section says "expanded / collapsed"* | phone |
| 11.2 | TalkBack → group page: swipe through the ledger → *day headers are headings (TalkBack "headings" navigation jumps day to day); a row reads e.g. "Food & drink, Pizza, €42.00, You paid, you lent €21.00" (+ "Has a note", "Not synced yet" when shown); the ⋮ per row is its own "Expense options" button; the app-bar cloud is announced as its status text ("Synced with everyone …" / "Waiting for …"), not as a disabled button; the title says "… Group settings"* | phone |
| 11.3 | TalkBack → add expense → *description is focused, keyboard open; every split mode readable: Equally — each checkbox "Anna, €5.00, checked"; Amounts / % — "Put the rest here" buttons; Shares — "One share more / less"; "%" segment read as "Percent"* | phone |
| 11.4 | TalkBack → balance page → *"Balances" / "Suggested payments" are headings; "How are payments suggested?" button; each person "gets back / owes" in words (not only colour)* | phone |
| 11.5 | System font size **200 %** (Settings → Display → Font size, max) → groups, group, add expense (all four split modes), balance, payment dialog, settings, group settings, people, backup page → *nothing overflows (no yellow-black stripes in debug); the currency field fades a long code instead of overflowing; amounts and names stay readable (ellipsis only where one line is intended)* | phone |
| 11.6 | Add expense (new), keyboard: *description focused on open → Next → amount (decimal keyboard with `,`/`.`) → Done closes the keyboard; the category picker sits after the date; editing an expense opens without a keyboard* | phone |
| 11.7 | Payment dialog from the app-bar action (amount blank) → *amount focused, decimal keyboard; Done with a valid amount records the payment*; from a tapped debt (prefilled) → *no keyboard on open* | phone |
| 11.8 | New group → *name focused; Next → the people field; Enter adds a chip and keeps the keyboard (G64)* | phone |

## 12. Review leftovers (G75)

| # | Step → expected | How |
|---|-----------------|-----|
| 12.1 | (G75) People → ⋮ → Rename a person to a name another person has → *hint "There is already … in this group", saving still allowed* | emu |
| 12.2 | (G75) Web build, first start → *groups page shows "MoneyLedger in the browser" (sync only while the tab is open, no restore points, data only in this browser); Got it → gone, also after a reload; About → "MoneyLedger in the browser" shows it again*; local mode → *the text without the sync part* | web |
| 12.3 | (G75) Local mode → delete an expense / a payment → *"… will be deleted from this device"* (not "for everyone") | emu |
| 12.4 | (G75) Export fails (e.g. cancel permissions / full storage) → *error snackbar with "Try again" + Details* | phone |

## 13. Link groups (G52, two devices, no accounts)

Real relays (nos.lol + nostr.mom). A = Pixel in local mode, B = emulator
(fresh install) unless noted; check `[link]` lines in logcat (debug builds
only). Landing page / App Link items need the `LeoStumpf.github.io` site
live.

| # | Step → expected | How |
|---|-----------------|-----|
| 13.1 | A: local group → ⋮ → *Invite with a link* → *first-use disclosure (nos.lol + nostr.mom, one operator, IP visible, Settings → Relays)* → *Continue* → sheet with QR + *Share link* / *Copy* | phone |
| 13.2 | B: scan A's QR with the camera app / open the shared link → *App Link opens the app directly (no browser)*; without verification → browser shows the landing page with *Open in MoneyLedger* → app | 2dev |
| 13.3 | B: *Join* → "Which person are you?" (A's people, A's own marked "used on another phone") → pick a person or *Someone new* → group opens; a fresh install starts local mode with that name | 2dev |
| 13.4 | A and B add / edit / delete expenses → *the other side shows it within seconds (live)*; group sync button → sheet lists the other phone as *has everything* | 2dev |
| 13.5 | B offline (airplane), A edits, B online → *B catches up at resume / next live subscription* | 2dev |
| 13.6 | B: swipe the app away, A edits, wait for a background round (or trigger the job, see G31) → *logcat `[bg] … link: true`, the change is there on next open* | 2dev |
| 13.7 | Settings → Relays: add a real custom relay (`wss://…`) → *NIP-11 check, listed with status*; remove it; *Use the default relays* | phone |
| 13.8 | A: *Reset invite link* → new link; B opens it → *"Switch to this link?"* → syncs again; a third device with only the old link stops getting A's changes | 2dev |
| 13.9 | B: delete the group → *A keeps it; B's events gone from nos.lol*; B restores a backup → banner "Which person are you?" → syncs again | 2dev |
| 13.10 | Web: open `https://<web app>/#/join?v=1&k=…` → join works; the secret never appears in a server request (DevTools → Network) | web |
| 13.11 | Landing page `https://leostumpf.github.io/moneyledger/join#v=1&k=…` in a desktop browser → *DevTools → Network: only same-origin requests, no fragment in any URL*; German browser → German texts; a cut-off link → "incomplete" | web |
| 13.12 | Offline demo (`OFFLINE_DEMO=true`) → *Climbing gym* shows synced, its invite sheet shows a QR; no network traffic | emu |

## 14. Mixed groups + lock (G53, Matrix accounts + a phone without one)

Real homeserver + real relays. A = Pixel signed in (@a), M = emulator
signed in (@m, same group), L = a second emulator / browser in local mode.

| # | Step → expected | How |
|---|-----------------|-----|
| 14.1 | A: Matrix group with M → ⋮ → *Invite with a link* → disclosure → *"Also share this group by link?"* → sheet; M's logcat `[link] bridging …`, M publishes too | 2dev |
| 14.2 | L opens the link, joins as someone new, adds an expense → *A and M show it, footer "Changed by … via link · not verified"* | 3dev |
| 14.3 | L: rename the group → *"Only possible with a Matrix account"*, nothing changes | phone |
| 14.4 | A: group settings → *Make group secure* → *dialog names L's person*; remove that person (or L connects a Matrix account → the person shows as claimed on A and M) → *Make group secure* → confirm → *snackbar; A's + M's channels gone (`[link] … was locked`), L shows the secure-only banner, read-only* | 3dev |
| 14.5 | A: *Invite with a link* again → *a new link (QR differs); M bridges again; L's old link finds nothing new* | 3dev |
| 14.6 | 360 dp, 200 % font, German: the confirmation, the "who still needs to sign in" dialog and the secure-only banner fit | phone |

## 15. "Why Matrix?" + welcome order (G54)

| # | Step → expected | How |
|---|-----------------|-----|
| 15.1 | Fresh install → welcome → *page 3 "Share a group with a link", page 4 "Want more security? Matrix" → Why Matrix? → 3 pages, last offers Sign in / Create account / Not now*; choices: *Start without an account* first, *Join with an invite link*, *Secure mode* below | emu |
| 15.2 | No account: a link group with 10 expenses → groups page *one-time card "There's also a secure mode"* → *Tell me more* → Why Matrix; back → card gone, also after a restart | emu |
| 15.3 | Link group ⋮ → *Why Matrix?* → last page *Connect a Matrix account* → login page (connect mode); link disclosure → *Why Matrix?* → last page only *Done* → back on the disclosure | emu |
| 15.4 | 360 dp, 200 % font, German, TalkBack: welcome choices, the three pages, the card and the "Kein Konto" chip fit; dots read as "Seite x von y" | phone |

## iOS

**iOS is not supported for v1.** The project is developed on Linux — there is no
macOS machine to build, sign or run iOS, and `flutter_vodozemac` (E2EE) needs an
iOS Rust/XCFramework build that has never been done. `ios/Runner` is template
level and has never been built. Nothing in this checklist has been run on iOS.

## Last run

**2026-10-17 (DEV-I, G63–G78 device pass)** · `d45b1ad` + DEV-I fixes ·
debug builds under a temporary id `io.github.leostumpf.moneyledger.devi`
(Leo's release install untouched; uninstalled afterwards): offline demo on
emu-5554 (`test-atd`, DE, 360 dp), a normal build in local mode on the
Pixel (DE). **3.11** ⋮ = *Person hinzufügen / Gruppe archivieren /
Gruppeneinstellungen*; settings page sections Konto / Synchronisierung /
Erweitert (Matrix) / Sichern & Wiederherstellen / Daten / Info (removed-group
variant not run — no such group in the demo). **8.16** page with „Was
brauchst du?“ (4 rows + the Matrix line) and the three blocks; **8.17**
*Gruppe auswählen …* → „Welche Gruppe?“ sorted → reset page (local mode /
read-only / web not run); **8.18** phone nudge *Jetzt sichern* → passphrase
dialog. **G64** Enter / Gboard ✓ adds a chip and keeps keyboard + focus
(Pixel), duplicate-name hint, *Person hinzufügen* buttons stack readable,
payer dropdown "Jonas — nicht mehr dabei". **G67** undo snackbar ≈ 7–8 s,
*Rückgängig* restores, archived banner + auto-unarchive (TalkBack, peer,
details sheet not run). **G69** share sheet with "wer zahlt wem" + overview.
**5.17** duplicate (single device; peer not run). **5.18** `12,50+8` →
20,50 €, `10/3` → 3,33 €; **Gboard's decimal keypad offers only `-`** (no
`+ * /`), `20-5` typed on it → 15,00 € — the calculator is unreachable for
`+ * /` on Android. **5.19** 15,56 / 12,22 / 2,22 → *Gleichmäßig* 15 / 12 / 3
→ Amounts "Ergibt den Gesamtbetrag"; items over the amount → "… zu viel" +
*Gesamtbetrag auf die Summe setzen* sets the form amount; items kept on
reopen (peer not run). **5.20** (Pixel) *Foto aufnehmen* → Google Camera, no
permission prompt; thumbnail + "Nur auf diesem Gerät …"; row icon;
`files/receipts/money_ledger_local/<id>.jpg` 1600×1200, 116 KB (dark shot),
EXIF kept, nothing left in `cache/`; full screen viewer; *Aus der Galerie
wählen* → system photo picker (cancelled — Leo's photos); *Ersetzen* →
"Belegfoto gespeichert"; *Entfernen* → "Belegfoto entfernt", file gone;
delete → *Rückgängig* keeps the file, delete again + force-stop + start →
gone; deleting a group removes its photo at once; local-mode delete text
„… wird von diesem Gerät gelöscht“ (12.3). **§11.5 (200 %)** found and fixed:
amounts cut in group cards / "Dein Saldo" / ledger rows / suggested payments,
split-mode labels broken mid-word, exact / item amount cells hiding the
value, former member's name pushed out, "Gesamtausgaben" broken mid-word,
monogram wrapping, *Begleichen* cut (`isLargeText` / `scaledCellWidth`,
`test/devi_large_font_test.dart`); re-checked on the emulator. 11.6 / 11.8
on the Pixel ✓ (description focused, Next → amount with the decimal keypad).
Not run: TalkBack 11.1–11.4, 11.7, 12.2 web, everything `2dev`.

**2026-10-17 (DEV-H, Phase H device pass)** · `2d496f5` (G59) · release APK
`install -r` over the pre-G45 1.0.0 install on the phone (A, DE — data and
session kept) and a fresh install on emu-5554 (`test-atd`, EN). **7.12:**
the `[g45]` line can't show in a release build (G44 silences all logging —
0 app lines in logcat); behaviour checked instead: sync after the update
works (emu signed in as B → "Restoring…" → the phone's startup digest
delivered both groups ≤ 5 s), expense emu → phone and phone → emu within
seconds, invite of B into a new group "DevH Invite" → on the emu ≤ 6 s, SAS
A → B's new device: same 7 emoji on both (📌 📌 🔔 ✂️ 🌙 🎩 🐱, Stecknadel /
Glocke / Schere / Mond / Hut / Katze in DE) → "Device verified" on both,
listed *Verifiziert*. `GET /presence/<mxid>/status` with a temporary curl
login (logged out afterwards): A and B `offline` (matrix.org reports no
`last_active_ago` at all, so this is weak evidence). Filter id check not
done (would mean reading the SDK store). **G46:** emu local mode → new group
opens directly ("Add people" CTA) → Android back → groups list; Settings →
*Delete local data* → welcome choices; the `money_ledger_local` file is gone.
Phone: new group opens directly too. **5.13/5.14:** phone *Neue Kategorie…*
"Dog" + paw on a new expense → emu's selector lists it under *This group*;
renamed to "Doggy" on the emu → phone shows "Doggy"; hidden on the emu →
phone's selector no longer offers it, the old expense keeps "Doggy".
**5.15:** phone expense dated Mon 12 Oct → emu lists it under "Mon, Oct 12";
edit prefills the date on both. **G59** (phone, 1080 px): Exact prefilled
2,50/2,50; clear B → "noch 2,50 € offen · Verteilen" + per-row *Rest hier
eintragen* → *Verteilen* → 2,50/2,50 "Ergibt den Gesamtbetrag"; % → 50/50;
Shares → steppers 1/1. Long names: both rows read "moneyledger-test-…" (Exact)
/ "moneyledger…" (Shares) — only the avatar initials tell them apart.
**8.13:** B (emu) deleted Hintergrund + Kino and edited Groceries → phone
*Auf früheren Stand zurücksetzen…* → "1 geändert · 2 gelöscht · von
moneyledger-test-b" → preview "2 Einträge kommen zurück · 1 Änderung wird
rückgängig gemacht" → "Gruppe zurückgesetzt (3 Änderungen)" → emu shows them
≤ 2 s, Groceries "Last edited by moneyledger-test-a". **Bug:** history entries
less than 10 min apart chain into one batch, and the first batch (the v12
backfill) is never resettable — so everything done within 10-minute gaps
after the update (or after a group is created / bootstrapped) is not
offered; the reset page was empty until a > 10 min pause. **8.14:** phone
Settings → *Wiederherstellungspunkte* lists "17. Okt. 2026 01:16 · 2
Gruppen · 5 Einträge", Restore → normal preview "Alles … schon auf diesem
Gerät" (`run-as` fails on the release build; the file
`files/snapshots/money_ledger_<hash>/2026-10-18.json` checked on the emu via
`adb root`). **8.15:** emu: solo group "DevH Solo" + expense, emu clock set a
day ahead (offline), app start → snapshot, delete the group → *Restore
points* → Restore ("left earlier — comes back") → group back; clock and
network restored afterwards. **G43:** `flutter build web --release
--no-web-resources-cdn`, headless Chrome + net log: welcome → login
untouched 15 s → only `127.0.0.1:8099` requests; *Check server* (matrix.org)
→ only `matrix.org/.well-known/matrix/client` +
`matrix-client.matrix.org/_matrix/client/v3/login` added (other hosts in
the net log are Chrome's own, no page initiator).

**2026-10-16 (G18 release check, v1.0.0+1)** · working tree on `e59fb91` +
G18 docs/G37 test · `./build.sh` green (979 tests) · release APK signed with
the upload key, `install -r` over the G38 installs on the phone (A, DE) and
emu-5554 (B, EN) — both kept their session and data. Groups page loads on
both ("Testgruppe A+B", "Lokal-Test", totals agree: €15.50 owed / owing).
Testgruppe on emu: *Add expense* "Release check" €1.00 equal → phone shows it
after ~3.3 s ("du schuldest 0,50 €"); deleted on emu → gone on the phone
after ~3.6 s, balances back to 3,50 € / €3.50, cloud "Synced" on both.
**0** `refused` / `[g6]` lines and no Flutter exceptions in either logcat.
Screenshots `g18f_*.png` (session scratchpad).

**2026-10-16 (G38 app id `io.github.leostumpf.moneyledger`, device reset)** ·
working tree on `4fa6995` + G38 · release APK signed with the upload key
(`aapt2 dump badging`: `package: name='io.github.leostumpf.moneyledger'`).
Old `app.moneyledger.money_ledger`: signed out in-app on the phone (A) and
emu-5554 (B) (logcat `SessionClearReason.logout`), then uninstalled there and
on emu-5556 (5556 killed afterwards). New APK installed on both. **Phone (DE),
true first open:** 1.1 welcome, 5 pages → *Ohne Konto nutzen* → "Leo A" →
local onboarding → group "Lokal-Test", Mia, Pizza 24 € equal → Settings →
*Matrix-Konto verbinden* (password login) → account onboarding, logcat
`[local] adopted 1 local group(s) into @…a… (4 rows signed)`, banner "Deine
lokale Gruppe gehört jetzt zu …". **emu-5554 (EN):** welcome → *Sign in with
Matrix* → B → onboarding → "Restoring your groups…". Phone: new group
"Testgruppe A+B" (EUR), invite B by MXID (no local person → added directly);
"Lokal-Test": invite B → "Who is …?" → *Mia* (claim) → emu shows "Lokal-Test
· You owe €12.00" (the adopted, freshly signed history). Testgruppe: Kino 30 €
(phone) → emu within ~4 s; Groceries 18.40 € (emu) → phone ≤ 2 s; Kino edited
to 36 € on emu → phone ≤ 2 s; "Loeschtest" 5 € added + deleted on phone → gone
on emu ≤ 2 s; payment B → A 8.80 € via *Settle up* (emu) → phone "Ausgeglichen";
cloud "Synchronisiert" / "Synced" on both; **0** `refused` / `[g6]` lines in
both logcats. 9.x SAS A → B (members page → ⋮ → Geräte → *Verifizieren*):
emu "Accept" → same 7 emoji, German names on the phone (Gitarre, Hammer, Uhr,
Daumen Hoch, Pokal, Elefant, Sanduhr), English on the emu → both "They match"
→ "Device verified" / "Gerät verifiziert", B's device listed "Verifiziert".
B's account also lists an "Element auf Chrome für Windows" session (not ours,
left alone). Background sync: emu job `androidx.work.systemjobscheduler/1`;
app task removed (`[bg-gate] app detached — releasing the app slot`; that
force stop made WorkManager reschedule as job 2), phone adds "Hintergrund" 7 €
→ `cmd jobscheduler run -f -n androidx.work.systemjobscheduler
io.github.leostumpf.moneyledger 2` → `[bg] round started for @…b…` →
`round done: … completed, received: 2, sent: 1` → phone cloud synced; emu
reopened shows "You owe €3.50". Final state: phone signed in as A, emu-5554
as B, both with "Testgruppe A+B" + "Lokal-Test" (the pre-G6 "G7a" groups are
gone). Screenshots `g38_*.png` (session scratchpad).

**2026-10-16 (G41 local-mode follow-ups)** · working tree on `dd5cf76` +
G41 · release APK. Spare emu-5556 (`zc-shot-phone`): uninstalled → fresh
install (EN) → local mode "Lea" → 1.13: group "G41 Local Trip", Kim, Dinner
€42 equal → unencrypted backup `Download/g41-local-backup.json` (`account:
local:self`); `app_flutter/` held `money_ledger_local.sqlite` before *Delete
local data* and was **empty** after it (login page). 1.14: signed in as test
account B (matrix.org SSO) → restore → preview with the takeover note, no
other-account warning → logcat `[backup] adopted 1 local-mode group(s) into
@moneyledger-test-b-c725:matrix.org (4 rows signed)`; Dinner shows "Added by
you". 1.15: emu-5554 (B's own device, only `install -r`) shows "G41 Local
Trip · 2 members · You are owed €21.00"; **0** `refused` lines in its logcat
after the restore (5556 logged the known G35 refusals of the pre-G6 "G7a"
groups from 5554). 1.16 not run on a device (unit tests only). 5556 signed
out and killed. Screenshots `g41_*.png` (session scratchpad).

**2026-10-16 (G39 welcome + G40 local mode)** · working tree on `cdb14e8` +
G39/G40 · release APK. Spare emu-5556 (`zc-shot-phone`): uninstalled → fresh
install (app locale DE): 1.1 welcome, 5 pages ("Ausgaben fair teilen" … "Wie
möchtest du starten?") → 1.7 *Ohne Konto nutzen* → name "Lea" → local
onboarding ("Alles bereit", 3 cards) → Groups with "Nur lokal" chip, no
devices / sign-out icons. 1.8: group "G40Local", Max + Ina (name-only dialog,
members hint, "Du (auf diesem Gerät)"), Pizza 30 € equal, Max → Lea 10 €
payment, balance "Ina zahlt an dich 10 €", backup nudge shown → *Alle Gruppen
sichern* (unencrypted) → `Download/moneyledger-backup-2026-10-16.json`, nudge
gone; no sync cloud. Relaunch in local mode: logcat shows **no**
`[client] buildMatrixClient` (first build of this pass still built one while
the device prefs loaded — fixed: transport / device gateway wait for the
prefs). App locale → EN: 1.6 About → *How MoneyLedger works* (4 pages, Done).
1.10: Settings → *Connect a Matrix account* → Cancel (back to local) → again →
signed in as test account B → logcat `[local] adopted 1 local group(s) into
@…b… (6 rows signed)`, account onboarding, banner "Your local group now
belongs to …". 1.11: emu-5554 (B's own device, app foreground) shows
"G40Local · 3 members · You are owed €10.00", Pizza + payment, "Synced with
all members"; **0** `refused` lines in its logcat (5556 logged the known
G35 refusals of the pre-G6 "G7a" groups from 5554 — recreated in G38). 1.12:
sign out → *Use without an account* → notice "Your earlier local groups were
moved into @…b…", empty ledger → *Delete local data* → "Delete all local
data?" → login page. 5556 signed out (device removed from B) and killed;
final APK `install -r` on emu-5554 (session kept) and the phone. Screenshots
`g40_*.png` (session scratchpad).

**2026-10-16 (G36+ follow-ups)** · working tree on `78c5b46` + G36+ ·
release APK via `adb install -r` on emu-5554 (B, EN) and phone (A, DE), no
logout / data clear; both kept their session, schema v8 migration ran
(emu logcat: `[db] deleted the adopted legacy ledger`). 7.9 (G7a Test, emu on
the group page): phone add → own cloud "Mit allen Mitgliedern
synchronisiert" after **9.4 / 9.7 / 9.8 / 11.2 s before → 5.7 / 5.7 / 5.4 /
6.0 s after** (uiautomator polling, ~2 s resolution). 7.10: emu wifi+data off
50 s → data on; data → wifi; wifi off → data; off 170 s → wifi on — each
time the phone's next expense was on the emulator within 2–3 s (before and
after the build; the stall seen once on emu-5556 was not reproduced; no
`[watchdog]` lines). 7.11 release: no debug entry in the settings sheet.
9.6: the verified-only subtitle + confirmation now say "only limits what this
device sends" and that a new own login can't restore from it until
verified (EN + DE); left off. 9.8: not run — every MoneyLedger device pair is
already verified (only Leo's Element session is unverified); covered by
widget tests. Balance page (DE): suggested payment "mone… zahlt an dich"
(NamesLine; the name ellipsizes, the words stay). Digest benchmark (5k
records, in-memory DB, separate `.bench` package, uninstalled afterwards) —
see open-points G37. Screenshots `g36_*.png` (session scratchpad).

**2026-10-16 (G34 backup follow-ups)** · working tree on `ce20a75` + G34/G35 ·
release APK via `adb install -r` on emu-5554 (B, EN) and phone (A, DE), no
logout / data clear. 8.8: emu → Back up all groups → passphrase (mismatch
shown, Save disabled; "Strength: strong") → "Encrypting…" → logcat
`[backup] encrypted in 1081 ms` → snackbar "Encrypted backup saved" (the
Downloads provider returned `/document/21`, so no name — as designed); the
file is the `moneyledger-backup-encrypted` wrapper, no group name in it.
8.9: restore it → wrong passphrase → "Wrong passphrase — or the file was
changed. Try again." → right one → preview "Encrypted backup — unlocked…",
"No new groups / Everything … already on this device", both groups "up to
date" → Restore → "Restored 2 groups", totals unchanged. 8.10: G7a Test ⋮ →
Back up this group → save dialog proposes
`moneyledger-backup-g7a-test-2026-10-16.json`; file holds 1 group (18
expenses incl. tombstones). 8.11: Leave group? → "Back up all groups first" →
passphrase dialog over it → saved → "Backup saved" shown **inside** the
leave dialog; leave cancelled. Phone (DE): "Sicherung schützen?" dialog,
encrypted export `[backup] encrypted in 806 ms` (Pixel 4a, Argon2id 32 MiB
t=3) → "Verschlüsselte Sicherung gespeichert" (the phone now shows a "last
backup" date). Test files deleted afterwards. Screenshots `g34_*.png`.

**2026-10-16 (G11 device verification)** · working tree on `81754eb` + G11 ·
release APK via `adb install -r` on phone (A, German), emu-5554 (B) and a
spare emu-5556 (fresh login as A, signed out afterwards — device removed).
9.2/9.4: SAS emu-5556 ↔ phone (A ↔ A): request popped up on the phone,
identical emojis (Trumpet Flower Pencil Key Ball Glasses Mushroom), "They
match" on both → phone "Gerät verifiziert."; emu-5556 hit a network drop
right after the MAC (the SDK's cancel send failed too, dialog stayed on the
spinner — now a 3-min stall timeout) but both device lists show the other
as **Verified**. 9.5: B → members → "3 unverified devices" under A → Verify
the phone → A accepted → emojis matched (Cloud Pizza Globe Penguin Dog Lion
Paperclip) → "Device verified." on both; one SAS verified both directions
(phone shows B's device Verified too). 9.6: phone (verified-only on, trusts
B + emu-5556) added "G11VerifiedOnly" → reached B and emu-5556. emu-5556
(verified-only on, B unverified there): members page "Not reachable — no
verified device", added "G11Withheld" with the phone app stopped → sync
tooltip "@…b… has no verified device", **B did not receive it** (≥70 s);
after restarting the phone (own verified device) it got it and relayed it
to B by anti-entropy (the phone trusts B — expected). 9.7: on B the details
of "G11Withheld" say "You haven't verified this device". Setting turned off
on every device afterwards. Screenshots `g11_*.png` (session scratchpad).
Seen: emu-5556's Matrix sync loop stalled after an emulator network switch
until the app was restarted; SAS emoji names are English (SDK) in the
German UI.

**2026-10-16 (G6 signed records, partial pass)** · working tree on `56416b7` ·
release APK installed with `adb install -r` on phone (A) and emu (B), no
logout / data clear. In group "G7a Test" (pre-G6 legacy rows): B added
"G6Signed" → A received it (footer "Hinzugefügt von <B>", no unverified
hint); A edited it (6 → 8 €) → B shows "Added by you · Last edited by <A>",
A "Hinzugefügt von <B> · Zuletzt bearbeitet von dir"; signature details on B:
both versions "Verified on receipt against the device's key"; A deleted the
legacy expense "LagProbe" (signed tombstone) → gone on B; both sync icons
cloud_done; no `[g6] refused` in logcat. Not covered on devices: forged
records (unit/integration tests), relay after logout, restore.

**2026-10-15** · build `88b4408` + working-tree fixes (registration web fallback,
local re-add — see G7 notes) · release APK signed with the upload key ·
phone = Pixel `09291JEC226042` (account A) · emu-B = AVD `zc` (account B) ·
emu-2 = AVD `zc-shot-phone` (logged-out flows, then A and B as extra devices;
signed out + data cleared afterwards). Items G7a already covered on 2026-10-14
(login, add/edit/delete, settlement, sync icon, offline repair, re-login) were
only re-checked where later changes touched them.

| # | Device | Result | Notes |
|---|--------|--------|-------|
| 1.1 | emu-2 | pass | login screen, matrix.org prefilled |
| 1.2 | all | known | label `money_ledger` (G12) |
| 1.3 | emu-2 | pass | onboarding shown right after login for A and again for B (per account); G25 delay not reproduced |
| 1.4 | phone, emu-B | pass | `install -r` + relaunch → Groups, session kept |
| 2.1 | emu-2 | pass | A and B password login |
| 2.2 | emu-2 | pass | shows raw `M_FORBIDDEN: Invalid username/password` (G20) |
| 2.3 | emu-2 | pass | label alternates "Continue with matrix-client.matrix.org" / "…matrix.org" (no IdP name) |
| 2.4 | emu-2 | pass | Chrome opens `matrix-client.matrix.org/…/sso/redirect?redirectUrl=moneyledger://sso-callback…` |
| 2.5 | — | not run | needs Leo (real SSO login) |
| 2.6 | emu-2 | pass | "SSO login failed: M_FORBIDDEN: Invalid login token", no crash |
| 2.7 | emu-2 | **fail → fixed** | matrix.org returns `M_FORBIDDEN` without UIA flows (registration moved to MAS) → raw "Registration failed" snackbar; now shows the web fallback |
| 2.8 | emu-2 | pass | opens https://matrix.org (home page, not the sign-up page) |
| 2.9 | — | not run | needs Leo + a dummy-UIA homeserver |
| 2.10 | emu-2 | pass | both extra devices gone from A's/B's device lists afterwards |
| 2.11 | emu-2 | pass | A → sign out → B: onboarding again, B's groups only, "You" = B |
| 3.1 | phone | pass | "G7 Smoke" created (returns to Groups) |
| 3.2/3.3 | phone, emu-B | pass | G7a Test EUR→USD→EUR; B (offline at the time) caught up on restart |
| 3.4 | emu-2 (A) | pass | "You are still owed 28.22 EUR" + export offer; B lists A under Former members |
| 3.6 | emu-B | pass | Delete group with "You still owe 20.39 EUR" warning |
| 4.1/4.4 | phone → emu-B | pass | local "Bea" linked to B's MXID → B receives the group, Bea = "You" |
| 4.3 | phone | pass | "Carl" local, usable in splits |
| 4.7 | phone | pass | Carl → Former members ("Local · former member") |
| 4.8 | phone, emu-B | **fail → fixed** | removed local person had no Re-add (only via "Add person" = duplicate "Carl"); now Re-add reactivates, replicated to B |
| 5.1 | phone | pass | 10.00/3 → 3.34/3.33/3.33; unticking Carl → 4.50/4.50 |
| 5.2 | phone | pass | "Remaining: EUR 2.00", Add disabled until "Adds up to the total" |
| 5.3 | phone | pass | 2:1:1 of 10.00 → 5.00/2.50/2.50 |
| 5.4 | phone | pass | 50/30/20 of 7.77 → 3.89/2.33/1.55 (sums exactly) |
| 5.5 | phone → emu-B | pass | Shares expense reopens as Exact; rename replicated |
| 5.6 | emu-B → phone | pass | |
| 5.7 | phone | known | keyboard covers the Add button (G17) |
| 6.1–6.3 | emu-B, phone | pass | B settles 23.73; listed on A ("Bea paid …"); A deletes → B's debt back |
| 6.4 | phone, emu-B | pass | 12.00 EUR + 15.00 USD shown separately |
| 7.1/7.2 | all | pass | A shows "Waiting for B…" for ~1 min after B's own change, then "Synced" |
| 7.3 | — | not run | needs a member account with no logged-in device (unit-tested) |
| 7.4 | emu-2 (B) | pass | airplane mode: add + delete → red cloud, sheet with error, Retry now → synced |
| 7.5/7.6 | emu-B | pass | emulator was down while A edited; caught up on restart |
| 7.7 | emu-2 | pass | fresh device (A, then B): all groups + history within ~3 s of onboarding |
| 7.8 | emu-2 → phone | pass | leaving on emu-2 removed the group from A's phone too |
| 8.1/8.2 | phone | pass | `Downloads/G7 Smoke.csv`, 4 rows, share columns per participant |
| 8.3 | phone | pass | re-import of the same file: no duplicate expenses/participants/group |
| 8.4 | — | not run | |
| 9.1 | phone, emu-B | pass | this device + Element web session ("Not verified") |
| 9.2/9.3 | — | not run | needs Leo (would pop up on his Element session) — 9.2 now covered app↔app, see G11 run |
| 10.1 | build | pass | `CN=Leo Stumpf, O=MoneyLedger` (upload key) |
| 10.2 | phone, emu-B | pass | upgrade kept session + data |
| 10.3 | build | pass | INTERNET (+ AndroidX `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`) only |
| 10.4 | — | not run | web build not exercised in this pass |
