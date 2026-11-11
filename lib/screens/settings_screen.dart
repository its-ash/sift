import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../sms/inbox_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});

  final InboxStore store;

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: const UiAppBar(title: 'Settings'),
      scrollable: true,
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final isSelf = store.defaultApp.isSelf;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiListGroup(
                header: 'Default SMS app',
                footer:
                    'Android lets only the default SMS app delete messages. Sift asks for the role when you '
                    'delete, then helps you switch back.',
                children: [
                  UiListTile(
                    'Current default',
                    icon: Icons.sms_rounded,
                    iconStatus: isSelf ? UiStatus.warning : UiStatus.success,
                    value: isSelf ? 'Sift' : (store.defaultApp.label ?? 'Unknown'),
                  ),
                  UiListTile(
                    isSelf ? 'Switch back to ${store.previousName}' : 'Default apps settings',
                    icon: Icons.swap_horiz_rounded,
                    chevron: true,
                    onTap: store.restoreDefault,
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              const UiListGroup(
                header: 'Privacy',
                children: [
                  UiListTile(
                    'Messages stay on this phone',
                    subtitle: 'Sorting happens on the phone. Sift uses the internet only to check for app updates.',
                    icon: Icons.lock_rounded,
                    iconStatus: UiStatus.success,
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              const UiUpdateSection(storeId: 'sift'),
              const UiGap(UiSpace.lg),
              const UiDeveloperSection(),
            ],
          );
        },
      ),
    );
  }
}
