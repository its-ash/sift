import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../sms/categorizer.dart';
import '../sms/inbox_store.dart';
import '../sms/sms_message.dart';
import 'delete_flow.dart';

/// The messages of one category. Tap to select, long-press to read the whole text.
class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key, required this.store, required this.category});

  final InboxStore store;
  final SmsCategory category;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = store.inCategory(category);
        final picked = [for (final m in list) if (store.selected.contains(m.id)) m.id];
        return UiScaffold(
          appBar: UiAppBar(title: category.label, subtitle: '${list.length} messages'),
          padding: EdgeInsets.zero,
          body: list.isEmpty
              ? UiEmptyState(icon: category.icon, title: 'Nothing left here', message: 'This category is empty.')
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: UiSpace.sm),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const UiDivider(indent: 64),
                  itemBuilder: (context, i) => _tile(context, list[i]),
                ),
          bottomBar: list.isEmpty
              ? null
              : UiBottomBar(
                  children: [
                    UiCheckbox(
                      store.selectionState(list),
                      tristate: true,
                      label: 'Select all',
                      onChanged: (_) => store.toggleAll(list),
                    ),
                    UiButton(
                      picked.isEmpty ? 'Delete' : 'Delete ${picked.length}',
                      icon: Icons.delete_rounded,
                      variant: UiButtonVariant.danger,
                      loading: store.deleting,
                      onPressed: picked.isEmpty ? null : () => confirmAndDelete(context, store, picked),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, SmsMessage m) {
    return UiListTile(
      m.sender,
      subtitle: m.body.replaceAll(RegExp(r'\s+'), ' ').trim(),
      leading: UiCheckbox(store.selected.contains(m.id), onChanged: (_) => store.toggle(m.id)),
      value: UiFormat.relativeTime(m.date),
      selected: store.selected.contains(m.id),
      onTap: () => store.toggle(m.id),
      onLongPress: () => UiDialog.alert(context, title: m.sender, message: m.body, icon: category.icon),
    );
  }
}
