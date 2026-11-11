import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import 'screens/home_screen.dart';
import 'sms/inbox_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SiftApp(store: InboxStore()));
}

class SiftApp extends StatelessWidget {
  const SiftApp({super.key, required this.store});

  final InboxStore store;

  @override
  Widget build(BuildContext context) {
    return UiApp(
      title: 'Sift',
      themeMode: ThemeMode.system,
      home: HomeScreen(store: store),
    );
  }
}
