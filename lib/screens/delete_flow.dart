import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:theme/theme.dart';

import '../sms/inbox_store.dart';
import '../sms/sms_platform.dart';

/// Confirm → become the default SMS app if needed → delete → offer to switch back.
///
/// Android lets only the default SMS app delete messages, so Sift takes the
/// role for the delete and then helps the user give it back.
Future<void> confirmAndDelete(BuildContext context, InboxStore store, Iterable<int> ids) async {
  final list = ids.toList();
  if (list.isEmpty) return;
  final n = list.length;
  final noun = n == 1 ? 'message' : 'messages';

  final ok = await UiDialog.confirm(
    context,
    title: 'Delete $n $noun?',
    message: 'They are removed from the SMS inbox on this phone. This cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!ok || !context.mounted) return;

  final app = await store.refreshDefaultApp();
  if (!context.mounted) return;
  if (!app.isSelf) {
    final go = await UiDialog.confirm(
      context,
      title: 'Set Sift as the SMS app',
      message:
          'Android only lets the default SMS app delete messages. On the next screen, pick Sift. '
          'When the delete is done, switch back to ${app.label ?? 'your messaging app'}.',
      confirmLabel: 'Continue',
      icon: Icons.swap_horiz_rounded,
    );
    if (!go || !context.mounted) return;
    final granted = await store.becomeDefault();
    if (!context.mounted) return;
    if (!granted) {
      context.showToast(
        'Sift was not set as the default SMS app, so nothing was deleted.',
        status: UiStatus.warning,
      );
      return;
    }
  }

  try {
    final deleted = await store.delete(list);
    if (!context.mounted) return;
    context.showToast('Deleted $deleted ${deleted == 1 ? 'message' : 'messages'}.', status: UiStatus.success);
  } on NotDefaultSmsAppException {
    if (context.mounted) {
      context.showToast('Sift is not the default SMS app, so nothing was deleted.', status: UiStatus.danger);
    }
    return;
  } on PlatformException catch (e) {
    if (context.mounted) {
      context.showToast(e.message ?? 'The delete failed.', title: 'Could not delete', status: UiStatus.danger);
    }
    return;
  }

  if (!context.mounted) return;
  await offerSwitchBack(context, store);
}

/// Asks the user to give the default SMS role back to their messaging app.
Future<void> offerSwitchBack(BuildContext context, InboxStore store) async {
  final app = await store.refreshDefaultApp();
  if (!app.isSelf || !context.mounted) return;
  final back = await UiDialog.confirm(
    context,
    title: 'Switch back to ${store.previousName}?',
    message:
        'Sift keeps new texts in your inbox while it is the default, but it does not show '
        'notifications or send messages. Pick ${store.previousName} on the next screen.',
    confirmLabel: 'Switch back',
    cancelLabel: 'Later',
    icon: Icons.undo_rounded,
  );
  if (back) await store.restoreDefault();
}
