import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../sms/inbox_store.dart';
import '../sms/role_state.dart';

/// Steps to turn on Android's "Allow restricted settings" for Sift, with a
/// button to open Sift's app page and a Retry.
///
/// Android 13+ blocks SMS permissions and the SMS role for apps installed from
/// an APK until the user allows it from Settings, Apps, Sift, three dots.
class RestrictedSettingsGuide extends StatelessWidget {
  const RestrictedSettingsGuide({super.key, required this.store, this.onRetry, this.showBanner = true});

  final InboxStore store;

  /// What Retry does. Defaults to asking for the SMS permission again.
  final VoidCallback? onRetry;

  /// Shows the lead banner. Off when the surrounding screen already says why.
  final bool showBanner;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBanner) ...[
          const UiBanner(restrictedSettingsSummary, status: UiStatus.warning),
          const UiGap(UiSpace.md),
        ],
        for (final g in restrictedSettingsGuides) ...[
          Text(g.heading, style: text.titleSmall),
          const UiGap(UiSpace.xs),
          for (var i = 0; i < g.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: UiSpace.xs),
              child: Text('${i + 1}. ${g.steps[i]}', style: text.bodyMedium?.copyWith(color: colors.textMuted)),
            ),
          const UiGap(UiSpace.sm),
        ],
        const UiGap(UiSpace.xs),
        UiButton(
          'Open Sift app settings',
          icon: Icons.open_in_new_rounded,
          onPressed: () => store.openAppDetails(),
        ),
        const UiGap(UiSpace.sm),
        UiButton(
          'Retry',
          icon: Icons.refresh_rounded,
          variant: UiButtonVariant.secondary,
          onPressed: onRetry ?? store.retryAfterRestricted,
        ),
      ],
    );
  }
}

/// Opens the guide in a sheet. Used when a request fails.
Future<void> showRestrictedGuideSheet(BuildContext context, InboxStore store, {VoidCallback? onRetry}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(UiSpace.lg, 0, UiSpace.lg, UiSpace.lg),
        child: RestrictedSettingsGuide(
          store: store,
          onRetry: () {
            Navigator.of(ctx).pop();
            (onRetry ?? store.retryAfterRestricted)();
          },
        ),
      ),
    ),
  );
}
