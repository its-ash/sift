# Sift (package: sift / com.itsash.sift)

Android SMS inbox cleaner. Reads the SMS inbox, sorts each message into a
category on the phone, and deletes a whole category, picked messages, or
everything.

## How deleting works

Android (4.4+) lets only the **default SMS app** write to or delete from the SMS
provider. Other apps' deletes silently remove nothing. So `delete_flow.dart`:
confirm → if Sift is not the default, explain, then
`requestDefaultSmsApp` (RoleManager `ROLE_SMS` on 10+, `ACTION_CHANGE_DEFAULT`
below) → `deleteMessages` → offer to switch back. Apps can request the role
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

## Code layout

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
