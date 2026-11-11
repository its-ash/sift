# Sift

Sort your SMS inbox into categories and delete them in bulk.

**[Website](https://sift.itsash.in)** · **[Download APK](https://github.com/its-ash/sift/releases/latest/download/sift.apk)** · Get it in **[Ash Store](https://store.itsash.in)**

## Features

- **Sorts your inbox** into OTPs & codes, Bank & payments, Orders & deliveries,
  Promotions & offers, Alerts & updates, and Personal. Understands Indian DLT
  sender ids (`VM-AMAZON-P` is promotional).
- **Delete by category**: tick a category to select all of it, or open it and
  pick single messages. Long-press a message to read all of it.
- **The whole SMS store**: received, sent, drafts and failed SMS, plus MMS
  (with their text). Each row has a chip such as `MMS · Sent`; filter by
  Received, Sent or MMS.
- **Select all** clears everything shown in one go. **Delete everything shown**
  asks twice and removes whole conversations where every message is selected.
- **Delete whole conversation**: long-press a message, then delete its thread
  (SMS and MMS together).
- **Asks before it deletes**, and shows how many SMS and MMS it removed.
- **RCS explainer** after a clean and in Settings, with a shortcut to Google
  Messages.
- **Private**: sorting happens on your phone. The only network call is the
  update check in Settings.

## Install

- **Ash Store**: install [Ash Store](https://store.itsash.in) once, then install and update Sift from it.
- **APK**: download the [latest APK](https://github.com/its-ash/sift/releases/latest/download/sift.apk) on your phone and open it. Allow your browser to install unknown apps if Android asks.

Requires Android 8.0 (API 26) or later.

### If Android blocks SMS access (Allow restricted settings)

On Android 13 and later, apps installed from an APK (not from a store) get
"Restricted settings": Android refuses the SMS permission and the default SMS
app request until you allow it. Symptoms: the permission prompt does not
appear or vanishes at once, or Sift cannot become the default SMS app.

- **Android 13**: Settings, Apps, Sift (See all apps if needed), tap the three
  dots at the top right, tap **Allow restricted settings**, confirm.
- **Android 14**: Settings, Apps, All apps, Sift, three dots at the top right,
  **Allow restricted settings**, confirm with your PIN or fingerprint.
- **Android 15 and later**: same path. The menu item appears only after you
  have tried to grant a permission once, so tap **Allow access** in Sift first,
  then open Settings, Apps, Sift, three dots, **Allow restricted settings**.

Then return to Sift and tap **Retry**. The same guide is in Sift under
Settings, Permissions. Installing through Ash Store may avoid the restriction.

Android lets only the **default SMS app** delete messages. When you delete,
Sift asks to become the default SMS app, deletes, then helps you switch
back to your messaging app. While Sift is the default, new texts are still
saved to your inbox, but you get no notifications for them, so switch back
right away.

## What Sift can't delete

Sift cannot read or delete **RCS chats**. Conversations marked "Chat" in Google
Messages are RCS. They live only inside Google Messages' own database, so no
third-party app can delete them (an Android limit, not a Sift bug).

- To clear them: open Google Messages, long-press the conversation, Delete.
- To stop receiving them: Messages, profile picture, Messages settings, RCS
  chats, turn off.
- If deleted SMS or MMS still appear in Google Messages, force-stop Google
  Messages or restart the phone; it can keep a stale thread list.

## Develop

Needs Flutter ≥ 3.44 and the shared theme package at `../theme`.

```bash
make run      # run on a connected device
make test     # flutter analyze + flutter test
make build    # release APK
make deploy   # bump version, build, tag, push, GitHub release (see store.mk)
```

## Release

`make deploy` follows the Ash Store kit (`store.mk`, `store.json`): it bumps the
version in `pubspec.yaml`, builds, commits, tags `vX.Y.Z`, pushes, and publishes
a GitHub release with `sift.apk`. Ash Store and the website pick up the new
version from that release.

## Project layout

```
lib/
├── main.dart                     # UiApp + HomeScreen
├── sms/
│   ├── categorizer.dart          # SmsCategory + keyword rules
│   ├── sms_message.dart          # one inbox message
│   ├── sms_platform.dart         # MethodChannel to MainActivity.kt
│   ├── sms_delete.dart           # chunked delete + exact counting (bridge)
│   ├── role_state.dart           # role state, restricted-settings logic and steps
│   └── inbox_store.dart          # inbox, selection, delete, default-app state
└── screens/
    ├── home_screen.dart          # categories, Select all, Delete
    ├── category_screen.dart      # messages of one category
    ├── delete_flow.dart          # confirm → take SMS role → delete → switch back
    ├── restricted_guide.dart     # "Allow restricted settings" guide
    └── settings_screen.dart
android/app/src/main/kotlin/com/itsash/sift/
├── MainActivity.kt               # read inbox, delete, default SMS role
├── SmsDeliverReceiver.kt         # saves new SMS while Sift is the default
└── RoleStubs.kt                  # components Android needs for the SMS role
```

See `CLAUDE.md` for details.

## License

No license file is included yet.

Built by [itsash.in](https://itsash.in).
