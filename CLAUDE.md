# Sift (package: sift / com.itsash.sift)

Android SMS inbox cleaner. Reads the whole SMS store (all boxes) and MMS, sorts
each message into a category on the phone, and deletes a whole category, picked
messages, whole conversations, or everything shown.

## What it cannot touch (RCS)

RCS chats ("Chat" in Google Messages) live only in Google Messages' private
database; no third-party app can read or delete them. `screens/rcs_card.dart`
(`RcsCard`) explains this, with "Open Google Messages" (`openGoogleMessages`:
launch intent for `com.google.android.apps.messaging`, falls back to the default
SMS app) and "Switch back" buttons plus a stale-thread hint. It shows after a
clean (with the summary "Removed N SMS and M MMS...") and always in Settings.
Keep it and the README section "What Sift can't delete" in sync.

## Messages and keys

`SmsMessage` has `kind` (sms/mms), `box` (received/sent/draft/other, from
`Sms.TYPE` / `Mms.MSG_BOX`) and `threadId`. SMS and MMS ids can collide, so the
selection holds `SmsMessage.key` (`id` for SMS, `-id` for MMS). MMS without text
shows "Picture/media message". `MessageFilter` (All/Received/Sent/MMS) filters
the list in `InboxStore`; changing it clears the selection.

## How deleting works

Android (4.4+) lets only the **default SMS app** write to or delete from the SMS
provider. Other apps' deletes silently remove nothing. So `delete_flow.dart`:
confirm → if Sift is not the default, explain, then
`requestDefaultSmsApp` (`RoleManager.createRequestRoleIntent(ROLE_SMS)` on 10+,
`ACTION_CHANGE_DEFAULT` below; returns `{granted, elapsedMs, error}`) →
`store.delete` (`planDelete` → `executeDelete`: SMS in chunks of 400 via
`content://sms` `_id IN (...)`, MMS the same via `content://mms`; a chunk that
removes fewer rows is retried per id; whole threads via
`content://mms-sms/conversations/<id>`; returns a `CleanSummary` with real
per-kind counts, thread counts taken from what is gone after the re-query; the
phone is re-queried after every delete; 0 is reported as an error; `SecurityException` →
channel code `security`) → offer to switch back. The role is checked with
`RoleManager.isRoleHeld(ROLE_SMS)` (or `getDefaultSmsPackage`) and shown in
Settings via `roleUiState`. Selection delete is by id (`planDelete` without
`useThreads`). "Delete whole conversation" (long-press a row) and "Delete
everything shown" (two UiDialog confirms) use `useThreads: true`: a thread where
every message is selected goes through thread deletion, the rest by id. Apps can request the role
only for themselves on 10+, so "switch back" opens the default apps screen;
below 10 it asks for the saved previous package directly. The previous
default's package and label are kept in `shared_preferences`.

To be eligible for the role the manifest must declare all four of:
`SmsDeliverReceiver` (SMS_DELIVER), `MmsDeliverReceiver` (WAP_PUSH_DELIVER),
`ComposeSmsActivity` (SENDTO sms/smsto), `HeadlessSmsSendService`
(RESPOND_VIA_MESSAGE). Do not remove any of them. While Sift holds the
role, `SmsDeliverReceiver` writes incoming SMS into the inbox so nothing is
lost; MMS is not saved and no notifications are shown. The home screen shows a
banner while Sift is the default.

## Restricted settings (Android 13+)

APK-installed apps get "Restricted settings": the SMS permission and the SMS
role are refused until the user opens Settings → Apps → Sift → ⋮ → Allow
restricted settings. `looksRestricted(sdk, outcome)` in `lib/sms/role_state.dart`
flags it (sdk ≥ 33, not granted, and the request failed or answered in under
600 ms, or loading the inbox threw a SecurityException). Then
`InboxStore.restrictedSuspected` is set and the UI shows
`screens/restricted_guide.dart` (steps for Android 13/14/15, "Open Sift app
settings" via `ACTION_APPLICATION_DETAILS_SETTINGS`, Retry): in the home
empty state, in a sheet when the role request fails, and always in Settings →
Permissions. The same steps are in README.md (Install). Keep all three in sync
(`restrictedSettingsGuides`).

## Code layout

- `lib/sms/role_state.dart`, `lib/sms/sms_delete.dart`, `lib/sms/sms_message.dart`:
  pure logic (role → UI state, restricted detection, `parseMessages`,
  `planDelete`, chunked per-kind delete counting over `SmsResolverBridge`).
  Tests: `test/role_state_test.dart`, `test/sms_delete_test.dart` (fake resolver /
  fake platform), `test/messages_test.dart` (combined parsing, thread vs id plans).

- `lib/sms/categorizer.dart`: `SmsCategory` (label, description, icon,
  `UiStatus`) and `SmsCategorizer.categorize(address, body)`. Rule order: OTP →
  bank → strong promo (score ≥ 2) → orders → weak promo (non-person sender) →
  personal (sender is a 7–15 digit phone number) → updates. Indian DLT sender
  suffix `-P` adds 2 to the promo score. Tests: `test/categorizer_test.dart`;
  add a case there for every rule change.
- `lib/sms/sms_platform.dart`: MethodChannel `com.itsash.sift/sms`
  (`defaultSmsApp`, `requestDefaultSmsApp`, `restoreDefaultSmsApp`,
  `loadMessages`, `deleteByIds`/`deleteById`, `deleteMmsByIds`/`deleteMmsById`,
  `deleteThreads`, `openGoogleMessages`). Categorizing runs in `Isolate.run`.
- `lib/sms/inbox_store.dart`: `ChangeNotifier` with status, messages grouped
  by category, the selection (`Set<int>` of `SmsMessage.key`s) and default-app state.
- `lib/screens/`: `home_screen.dart` (categories with tristate checkboxes,
  Select all + Delete bottom bar), `category_screen.dart`, `delete_flow.dart`,
  `settings_screen.dart`.
- `android/app/src/main/kotlin/com/itsash/sift/MainActivity.kt`: channel
  handlers; reads `content://sms` (all types) and `content://mms` (text part,
  addr 137/151), deletes by `_id IN (...)` in chunks of 400 on a background
  executor.

## Commands

- `make run`, `make build` (release APK), `make test` (`flutter analyze` +
  `flutter test`), `make clean`.
- Icon: SVG sources in `assets/icon/` (`logo`, `logo_foreground`,
  `logo_background`) → `rsvg-convert -w 1024 -h 1024` to `*-1024.png`, then
  `dart run flutter_launcher_icons`.

## Conventions

- minSdk 26. UI only from the shared `theme` package (`../theme`, read
  `../theme/COMPONENTS.md`); no hardcoded colors.
- Only network use: `UiUpdateSection` in Settings (needs `INTERNET`). No
  analytics or telemetry.

## Release (Ash Store)

- `store.json` (id `sift`, repo its-ash/sift), `store.mk`,
  `index.html` + `CNAME` (`sift.itsash.in`). See
  `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version → build → commit, tag `vX.Y.Z`, push → GitHub
  release with `sift.apk` → topics, homepage, Pages. Never create releases,
  tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run
  `make store-sync` at the workspace root.
