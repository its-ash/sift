# Sift

Sort your SMS inbox into categories and delete them in bulk.

**[Website](https://sift.itsash.in)** · **[Download APK](https://github.com/its-ash/sift/releases/latest/download/sift.apk)** · Get it in **[Ash Store](https://store.itsash.in)**

## Features

- **Sorts your inbox** into OTPs & codes, Bank & payments, Orders & deliveries,
  Promotions & offers, Alerts & updates, and Personal. Understands Indian DLT
  sender ids (`VM-AMAZON-P` is promotional).
- **Delete by category**: tick a category to select all of it, or open it and
  pick single messages. Long-press a message to read all of it.
- **Select all** clears the whole inbox in one go.
- **Asks before it deletes**, and shows how many messages it removed.
- **Private**: sorting happens on your phone. The only network call is the
  update check in Settings.

## Install

- **Ash Store**: install [Ash Store](https://store.itsash.in) once, then install and update Sift from it.
- **APK**: download the [latest APK](https://github.com/its-ash/sift/releases/latest/download/sift.apk) on your phone and open it. Allow your browser to install unknown apps if Android asks.

Requires Android 8.0 (API 26) or later.

Android lets only the **default SMS app** delete messages. When you delete,
Sift asks to become the default SMS app, deletes, then helps you switch
back to your messaging app. While Sift is the default, new texts are still
saved to your inbox, but you get no notifications for them, so switch back
right away.

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
│   └── inbox_store.dart          # inbox, selection, delete, default-app state
└── screens/
    ├── home_screen.dart          # categories, Select all, Delete
    ├── category_screen.dart      # messages of one category
    ├── delete_flow.dart          # confirm → take SMS role → delete → switch back
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
