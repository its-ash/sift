import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:theme/theme.dart';

import '../sms/categorizer.dart';
import '../sms/inbox_store.dart';
import '../sms/role_state.dart';
import 'category_screen.dart';
import 'delete_flow.dart';
import 'restricted_guide.dart';
import 'settings_screen.dart';

/// The inbox sorted into categories. Tick categories (or Select all) and delete.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final InboxStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppLifecycleListener _lifecycle;

  InboxStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.init();
    // Coming back from the system "default SMS app" or permission screens.
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  Future<void> _onResume() async {
    await store.refreshDefaultApp();
    if (store.status == InboxStatus.needsPermission || store.status == InboxStatus.permanentlyDenied) {
      if (await Permission.sms.isGranted) await store.load();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(store: store)));

  void _openCategory(SmsCategory c) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CategoryScreen(store: store, category: c)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final ready = store.status == InboxStatus.ready && store.total > 0;
        return UiScaffold(
          appBar: UiAppBar(
            title: 'Sift',
            actions: [
              UiIconButton(
                Icons.refresh_rounded,
                tooltip: 'Reload inbox',
                onPressed: store.status == InboxStatus.ready && !store.deleting ? store.load : null,
              ),
              UiIconButton(Icons.settings_rounded, tooltip: 'Settings', onPressed: _openSettings),
            ],
          ),
          padding: EdgeInsets.zero,
          body: _body(context),
          bottomBar: ready ? _bottomBar(context) : null,
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    switch (store.status) {
      case InboxStatus.loading:
        return const Center(child: UiSpinner(size: 28));
      case InboxStatus.needsPermission:
        if (store.restrictedSuspected) return _restrictedBody(context);
        return UiEmptyState(
          icon: Icons.sms_rounded,
          title: 'Allow SMS access',
          message: 'Sift reads your SMS inbox to sort it into categories. Your messages never leave this phone.',
          action: UiButton('Allow access', icon: Icons.lock_open_rounded, onPressed: store.requestPermission),
        );
      case InboxStatus.permanentlyDenied:
        if (store.restrictedSuspected || store.role.sdk >= restrictedSettingsMinSdk) return _restrictedBody(context);
        return const UiEmptyState(
          icon: Icons.sms_failed_rounded,
          title: 'SMS access is off',
          message: 'Turn on the SMS permission for Sift in Android settings, then come back.',
          action: UiButton('Open app settings', icon: Icons.open_in_new_rounded, onPressed: openAppSettings),
        );
      case InboxStatus.error:
        return UiErrorState(message: store.error ?? 'Could not read the inbox.', onRetry: store.load);
      case InboxStatus.ready:
        if (store.total == 0) {
          return const UiEmptyState(
            icon: Icons.mark_email_read_rounded,
            title: 'Inbox is empty',
            message: 'There are no SMS messages to clean up.',
          );
        }
        return _categoryList(context);
    }
  }

  Widget _restrictedBody(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(UiContent.pagePadding(context)),
      children: [
        Text('SMS access is blocked', style: context.text.headlineSmall),
        const UiGap(UiSpace.sm),
        RestrictedSettingsGuide(store: store),
      ],
    );
  }

  Widget _categoryList(BuildContext context) {
    final text = context.text;
    final colors = context.colors;
    return ListView(
      padding: EdgeInsets.fromLTRB(UiContent.pagePadding(context), UiSpace.lg, UiContent.pagePadding(context), UiSpace.xl),
      children: [
        if (store.defaultApp.isSelf) ...[
          UiBanner(
            'Sift is your default SMS app. New texts are saved but you get no notifications and cannot reply. '
            'Switch back to ${store.previousName} when you are done cleaning.',
            status: UiStatus.warning,
            actionLabel: 'Switch back',
            onAction: store.restoreDefault,
          ),
          const UiGap(UiSpace.lg),
        ],
        Text('${store.total} messages', style: text.headlineSmall),
        const UiGap(UiSpace.xs),
        Text(
          'Sorted on this phone into ${store.categories.length} categories. Tick a category to select all of it, or open it to pick messages.',
          style: text.bodyMedium?.copyWith(color: colors.textMuted),
        ),
        const UiGap(UiSpace.lg),
        UiListGroup(
          header: 'Categories',
          children: [for (final c in store.categories) _categoryTile(c)],
        ),
      ],
    );
  }

  Widget _categoryTile(SmsCategory c) {
    final list = store.inCategory(c);
    final picked = store.selectedIn(c);
    return UiListTile(
      c.label,
      subtitle: picked == 0 ? c.description : '$picked of ${list.length} selected',
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UiCheckbox(store.selectionState(list), tristate: true, onChanged: (_) => store.toggleAll(list)),
          const UiGap(UiSpace.sm),
          UiIconBox(c.icon, status: c.status),
        ],
      ),
      value: '${list.length}',
      chevron: true,
      onTap: () => _openCategory(c),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final all = store.selectionState(store.messages);
    final n = store.selectedCount;
    return UiBottomBar(
      children: [
        UiCheckbox(all, tristate: true, label: 'Select all', onChanged: (_) => store.toggleAll(store.messages)),
        UiButton(
          n == 0 ? 'Delete' : 'Delete $n',
          icon: Icons.delete_rounded,
          variant: UiButtonVariant.danger,
          loading: store.deleting,
          onPressed: n == 0 ? null : () => confirmAndDelete(context, store, store.selected.toList()),
        ),
      ],
    );
  }
}
