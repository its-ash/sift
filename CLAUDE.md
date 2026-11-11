# Sift (package: sift / com.itsash.sift)

Android SMS inbox cleaner. Reads the SMS inbox, sorts each message into a
category on the phone, and deletes a whole category, picked messages, or
everything.

## How deleting works

Android (4.4+) lets only the **default SMS app** write to or delete from the SMS
provider. Other apps' deletes silently remove nothing. So `delete_flow.dart`:
confirm → if Sift is not the default, explain, then
`requestDefaultSmsApp` (`RoleManager.createRequestRoleIntent(ROLE_SMS)` on 10+,
`ACTION_CHANGE_DEFAULT` below; returns `{granted, elapsedMs, error}`) →
`store.delete` (chunks of 400 via `content://sms` `_id IN (...)`, a chunk that
removes fewer rows is retried per id via `content://sms/<id>`; returns a
`DeleteResult(requested, deleted)`; the inbox is re-queried afterwards; the toast
shows the real count, 0 is reported as an error; `SecurityException` →
channel code `security`) → offer to switch back. The role is checked with
`RoleManager.isRoleHeld(ROLE_SMS)` (or `getDefaultSmsPackage`) and shown in
Settings via `roleUiState`. `deleteThreads` (`content://mms-sms/conversations/<id>`)
exists on the channel but the UI deletes by message id. Apps can request the role
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

- `lib/sms/role_state.dart`, `lib/sms/sms_delete.dart`: pure logic (role →
  UI state, restricted detection, chunked delete counting over
  `SmsResolverBridge`). Tests: `test/role_state_test.dart`,
  `test/sms_delete_test.dart` (fake resolver / fake platform).

- `lib/sms/categorizer.dart`: `SmsCategory` (label, description, icon,
  `UiStatus`) and `SmsCategorizer.categorize(address, body)`. Rule order: OTP →
  bank → strong promo (score ≥ 2) → orders → weak promo (non-person sender) →
  personal (sender is a 7–15 digit phone number) → updates. Indian DLT sender
  suffix `-P` adds 2 to the promo score. Tests: `test/categorizer_test.dart`;
  add a case there for every rule change.
- `lib/sms/sms_platform.dart`: MethodChannel `com.itsash.sift/sms`
  (`defaultSmsApp`, `requestDefaultSmsApp`, `restoreDefaultSmsApp`,
  `loadInbox`, `deleteMessages`). Categorizing runs in `Isolate.run`.
- `lib/sms/inbox_store.dart`: `ChangeNotifier` with status, messages grouped
  by category, the selection (`Set<int>` of SMS ids) and default-app state.
- `lib/screens/`: `home_screen.dart` (categories with tristate checkboxes,
  Select all + Delete bottom bar), `category_screen.dart`, `delete_flow.dart`,
  `settings_screen.dart`.
- `android/app/src/main/kotlin/com/itsash/sift/MainActivity.kt`: channel
  handlers; reads `Telephony.Sms.Inbox`, deletes by `_id IN (...)` in chunks of
  400 on a background executor.

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
