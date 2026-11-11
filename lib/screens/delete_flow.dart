import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:theme/theme.dart';

import '../sms/inbox_store.dart';
import '../sms/role_state.dart';
import '../sms/sms_delete.dart';
import '../sms/sms_message.dart';
import '../sms/sms_platform.dart';
import 'restricted_guide.dart';

/// Confirm → become the default SMS app if needed → delete → offer to switch back.
///
/// Android lets only the default SMS app delete messages, so Sift takes the
/// role for the delete and then helps the user give it back.
/// [keys] are [SmsMessage.key]s (SMS and MMS) deleted by id.
Future<void> confirmAndDelete(BuildContext context, InboxStore store, Iterable<int> keys) async {
  final list = keys.toList();
  if (list.isEmpty) return;
  final n = list.length;
  final noun = n == 1 ? 'message' : 'messages';

  final ok = await UiDialog.confirm(
    context,
    title: 'Delete $n $noun?',
    message: 'They are removed from the SMS and MMS store on this phone. This cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await _performDelete(context, store, () => store.delete(list));
}

/// Deletes the whole conversation (SMS + MMS) that [m] belongs to.
Future<void> confirmDeleteConversation(BuildContext context, InboxStore store, SmsMessage m) async {
  final inThread = store.allMessages.where((x) => x.threadId == m.threadId).length;
  final ok = await UiDialog.confirm(
    context,
    title: 'Delete whole conversation?',
    message:
        'All ${m.threadId > 0 ? inThread : 1} messages (SMS and MMS, sent and received) with ${m.sender} '
        'are removed from this phone. This cannot be undone.',
    confirmLabel: 'Delete conversation',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await _performDelete(context, store, () => store.deleteConversation(m.threadId));
}

/// Deletes everything the current filter shows, after two confirmations.
Future<void> confirmDeleteShown(BuildContext context, InboxStore store) async {
  final n = store.total;
  if (n == 0) return;
  final first = await UiDialog.confirm(
    context,
    title: 'Delete everything shown?',
    message:
        'This deletes all $n ${store.filter.label.toLowerCase()} messages listed here, including whole '
        'conversations where every message is shown.',
    confirmLabel: 'Continue',
    destructive: true,
  );
  if (!first || !context.mounted) return;
  final second = await UiDialog.confirm(
    context,
    title: 'Really delete $n messages?',
    message: 'This cannot be undone. Nothing is backed up.',
    confirmLabel: 'Delete $n',
    destructive: true,
  );
  if (!second || !context.mounted) return;
  await _performDelete(context, store, store.deleteShown);
}

Future<void> _performDelete(BuildContext context, InboxStore store, Future<CleanSummary> Function() run) async {
  final app = await store.refreshDefaultApp();
  if (!context.mounted) return;
  if (store.roleUi == SmsRoleUiState.unavailable) {
    context.showToast(
      'This phone has no default SMS app role, so Sift cannot delete messages.',
      status: UiStatus.danger,
    );
    return;
  }
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
      if (store.restrictedSuspected) {
        var retry = false;
        await showRestrictedGuideSheet(context, store, onRetry: () => retry = true);
        if (retry && context.mounted) await _performDelete(context, store, run);
        return;
      }
      context.showToast(
        'Sift was not set as the default SMS app, so nothing was deleted.',
        status: UiStatus.warning,
      );
      return;
    }
  }

  try {
    final result = await run();
    if (!context.mounted) return;
    if (result.removed == 0) {
      context.showToast(
        'Android reported 0 messages deleted. Sift may not really be the default SMS app, or the messages are protected.',
        title: 'Nothing deleted',
        status: UiStatus.danger,
      );
    } else if (!result.complete) {
      context.showToast(
        'Removed ${result.removedSms} SMS and ${result.removedMms} MMS. '
        '${result.failed} could not be removed.',
        status: UiStatus.warning,
      );
    } else {
      context.showToast(result.message, status: UiStatus.success);
    }
  } on SmsSecurityException catch (e) {
    if (context.mounted) {
      context.showToast(e.message, title: 'Android blocked the delete', status: UiStatus.danger);
    }
    return;
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
        'notifications or send messages. Open the default apps screen and pick ${store.previousName} '
        'as the SMS app.',
    confirmLabel: 'Switch back',
    cancelLabel: 'Later',
    icon: Icons.undo_rounded,
  );
  if (back) await store.restoreDefault();
}
