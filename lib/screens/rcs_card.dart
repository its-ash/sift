import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../sms/inbox_store.dart';

const rcsExplainer =
    "Conversations marked 'Chat' in Google Messages are RCS. They live only inside Google Messages, "
    'so no other app can delete them. To clear them: open Google Messages, long-press the conversation '
    '→ Delete. To stop receiving them: Messages → profile picture → Messages settings → RCS chats → '
    'turn off.';

const rcsStaleHint = 'If deleted messages still appear, force-stop Google Messages or restart the phone';

/// Explains what Sift cannot delete (RCS) and how to clear it in Google
/// Messages. Shown after a clean (with the [summary]) and in Settings.
class RcsCard extends StatelessWidget {
  const RcsCard({super.key, required this.store, this.summary, this.onDismiss});

  final InboxStore store;

  /// What the clean just removed, shown first.
  final String? summary;
  final VoidCallback? onDismiss;

  Future<void> _open(BuildContext context) async {
    final result = await store.openGoogleMessages();
    if (result == 'none' && context.mounted) {
      context.showToast('No messaging app could be opened.', status: UiStatus.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    return UiSection(
      title: 'RCS chats',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary != null) ...[
            UiBanner(summary!, status: UiStatus.success, onDismiss: onDismiss),
            const UiGap(UiSpace.md),
          ],
          const UiBanner(rcsExplainer),
          const UiGap(UiSpace.sm),
          const UiBanner(rcsStaleHint, status: UiStatus.warning),
          const UiGap(UiSpace.md),
          UiButton(
            'Open Google Messages',
            icon: Icons.open_in_new_rounded,
            variant: UiButtonVariant.secondary,
            onPressed: () => _open(context),
          ),
          const UiGap(UiSpace.sm),
          UiButton(
            'Switch back to Google Messages',
            icon: Icons.undo_rounded,
            variant: UiButtonVariant.secondary,
            onPressed: store.restoreDefault,
          ),
        ],
      ),
    );
  }
}
