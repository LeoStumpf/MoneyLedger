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
| 1.1 | Fresh install, launch → *login screen ("MoneyLedger / Sign in with your Matrix account"), homeserver prefilled `matrix.org`, no crash* | emu |
| 1.2 | Launcher label + icon → *app name and icon shown (currently `money_ledger` + Flutter default, see G12)* | emu |
| 1.3 | First login of an account on this device → *onboarding "Welcome to MoneyLedger" shown once; "Get started" → Groups* | emu |
| 1.4 | Kill + relaunch → *goes straight to Groups (session restored, no onboarding, no hang on a slow sync)* | emu |
| 1.5 | Airplane mode, relaunch → *Groups and all local data shown offline* | emu |

## 2. Login, registration, account switch

| # | Step → expected | How |
|---|-----------------|-----|
| 2.1 | Password login (homeserver, username, password) → *Groups (or onboarding)* | emu |
| 2.2 | Wrong password → *error shown, stays on login, no crash* | emu |
| 2.3 | Homeserver with SSO (matrix.org) → *"Continue with …" SSO button appears after the flow lookup* | emu |
| 2.4 | Tap an SSO button → *system browser opens the homeserver SSO page* | emu |
| 2.5 | Complete SSO in the browser → *`moneyledger://sso-callback?loginToken=…` returns to the app, signed in* | Leo |
| 2.6 | Signed out: `adb shell am start -a android.intent.action.VIEW -d "moneyledger://sso-callback?loginToken=invalid" app.moneyledger.money_ledger` → *"SSO login failed: …" snackbar, stays on login, no crash* | emu |
| 2.7 | Login → "New here? Create an account" → fill dummy username/password (no account is created on matrix.org: it disabled client registration / needs captcha etc.) → Create account → *"Register on the web" card ("signing up on its own website" for matrix.org, or the required UIA stages) + "Open homeserver website"* | emu |
| 2.8 | "Open homeserver website" → *browser opens the homeserver* | emu |
| 2.9 | Registration on a homeserver with an open `m.login.dummy` flow → *account created, signed in* | Leo |
| 2.10 | Sign out (Groups app bar; no confirmation) → *back on login; the device disappears from the account's device list; local data stays on disk (per-account DB)* | emu |
| 2.11 | Sign in as a different account on the same device → *onboarding again (per-account flag), then only that account's groups (recovered from its other device), "You" = that account*; sign back in as the first → *its groups are back* | 2dev |

## 3. Groups

| # | Step → expected | How |
|---|-----------------|-----|
| 3.1 | "New group" → name + currency → Create → *back on Groups, new group listed* | emu |
| 3.2 | ⋮ → Edit group: rename + change default currency → *title/list updated; peer shows new name* | 2dev |
| 3.3 | New expense after currency change → *uses the new currency (the form has no per-expense currency picker — the group default is used)* | emu |
| 3.4 | ⋮ → Leave group (shared group, you are a member) → *warning "You are still owed …" + "Back up all groups first"; group disappears; peer sees you under "Former members"* | 2dev |
| 3.5 | Re-add the leaver from the peer → *group comes back on the leaver's device with full history* | 2dev |
| 3.6 | ⋮ → Delete group (solo/local-only group, or every other claimed member left) → *balance warning; "Deleted …" snackbar; group gone from this device* | emu |
| 3.7 | Removed by a peer → *banner "You were removed from this group", history read-only, "Delete from this device"* | 2dev |
| 3.8 | ⋮ → Archive group → *back on Groups; group in the collapsed "Archived (N)" section; snackbar Undo works; totals unchanged* (G16) | emu |
| 3.9 | Peer adds an expense to the archived group → *group is back among the active groups by itself* (G16) | 2dev |
| 3.10 | Open an archived group → *"archived on this device" banner*; ⋮ / banner → Unarchive → *back in the list* (G16) | emu |

## 4. Members

| # | Step → expected | How |
|---|-----------------|-----|
| 4.1 | Members → "Invite by Matrix ID" with B's MXID → *B listed (Matrix); B's device receives the group (bootstrap)* | 2dev |
| 4.2 | Invite an invalid ID (`bob`) → *"Invalid Matrix ID"* | emu |
| 4.3 | "Add person" (name only) → *listed as "Local"; usable as payer / in splits* | emu |
| 4.4 | Local person → ⋮ Link Matrix account (MXID) → *shows the MXID; that account now receives the group* | 2dev |
| 4.5 | A device that received the group but whose MXID claims no participant → *banner "Which participant are you?" → Choose: pick a local person (self-claim) or "I'm someone new" + name; replicates* | 2dev |
| 4.6 | ⋮ Rename / Detach Matrix account → *name changes everywhere; history keeps the participant* | emu |
| 4.7 | ⋮ Remove from group → *moves to "Former members" (greyed, "Re-add"); expenses still show the name* | emu |
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
| 5.8 | Type "Pizza" → *Food & drink chip preselected*; pick another chip → *typing no longer changes it*; tap the selected chip → *none* (G16) | emu |
| 5.9 | Add a category + note → *category icon in the list, note icon after the title; peer shows the same icon + note (DE labels on a German device)* (G16) | 2dev |
| 5.10 | 🔍 in the group app bar → type part of a description / note / payer → *list filtered, "N entries"*; category chips + "Involving me" narrow it; nothing found → *"Clear filters"* (G16) | emu |

## 6. Settlements & balances

| # | Step → expected | How |
|---|-----------------|-----|
| 6.1 | Balance → tap **your own** debt row (only the debtor can) → Record settlement → Confirm → *debt cleared here and on the peer* | 2dev |
| 6.2 | Expense list → *settlement shown (handshake icon, "A paid B", date)* | emu |
| 6.3 | Settlement ⋮ Delete → *gone; balance restored; peer too* | 2dev |
| 6.4 | Edit group → default currency USD → add an expense → *balance page shows separate EUR and USD debts, no conversion* (then delete it + switch back) | emu |
| 6.5 | Everything settled → *"All settled up!"* | emu |
| 6.6 | Balance → ⓘ next to "Suggested payments" → *"Simplified debts" explanation*; multi-currency group → *"settled separately per currency" note* (G16) | emu |

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

## 8. Backup (JSON) and CSV

| # | Step → expected | How |
|---|-----------------|-----|
| 8.1 | Expenses ⋮ → Export CSV → *system save dialog ("<group>.csv"); saved to Downloads; "Exported …" snackbar* | phone |
| 8.2 | Open the CSV in a sheet app → *one row per expense, then one per payment (Type "Payment"), decimal amounts, a share column per participant* | phone |
| 8.3 | Groups → Import CSV → pick the same file → *preview "Merges into your group …"; no duplicate expenses/payments/group (idempotent merge)* | phone |
| 8.4 | Import into a device that lacks the group → *group created with its participants (local by name)* | phone |
| 8.5 | Settings (gear) → Back up all groups → *save dialog `moneyledger-backup-YYYY-MM-DD.json`; "Backup saved"; settings shows "Last backup: <today>"* | phone |
| 8.6 | Settings → Restore from backup → pick that file → *preview "No new groups … already on this device"; Restore → "Restored N groups", nothing duplicated* | phone |
| 8.7 | Solo group (no other Matrix member), no backup for 30 days → *"Back up your groups" card on the groups page; Later hides it for 30 days* | phone |

## 9. Devices & verification

| # | Step → expected | How |
|---|-----------------|-----|
| 9.1 | Groups → Devices & security → *all of the account's devices listed (this one first) with verified status* | emu |
| 9.2 | "Verify" another own device → *emoji dialog on both; "They match" on both → "Device verified."* | Leo |
| 9.3 | Cancel mid-verification → *dialog closes, no crash, device stays unverified* | Leo |
| 9.4 | The other device shows "Verification request … Accept / Decline" on any screen → Accept → *same emoji dialog* | emu |
| 9.5 | Members → tap "N unverified devices" under a member (or ⋮ → Devices) → Verify their device; they accept → *emoji dialog on both; both "Device verified."; the member's device and ours show Verified on both sides* | emu |
| 9.6 | Settings → "Only sync with verified devices" → *confirmation explains the consequence*; on → add an expense → *verified devices (own + peers) get it; a member with no verified device: members page red "Not reachable — no verified device", sync tooltip "X has no verified device …", they don't receive it* | emu |
| 9.7 | Signature details of a record from a device you haven't verified → *"You haven't verified this device (emoji comparison)."* | emu |

## 10. Release build

| # | Step → expected | How |
|---|-----------------|-----|
| 10.1 | `flutter build apk --release` → *succeeds; signed with the release keystore (`apksigner verify --print-certs`), not the debug key* | emu |
| 10.2 | `adb install -r` over the previous release → *upgrade keeps session and data* | emu |
| 10.3 | Permissions (`aapt dump permissions` / app info) → *INTERNET only (+ plugin-merged ones); no storage permission needed for export/import* | emu |
| 10.4 | Web: `flutter build web --release`, serve `build/web` → *login, E2EE init (vodozemac wasm), sync works* | emu |

## iOS

**iOS is not supported for v1.** The project is developed on Linux — there is no
macOS machine to build, sign or run iOS, and `flutter_vodozemac` (E2EE) needs an
iOS Rust/XCFramework build that has never been done. `ios/Runner` is template
level and has never been built. Nothing in this checklist has been run on iOS.

## Last run

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
