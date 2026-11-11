import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'categorizer.dart';
import 'role_state.dart';
import 'sms_delete.dart';
import 'sms_message.dart';
import 'sms_platform.dart';

enum InboxStatus { loading, needsPermission, permanentlyDenied, error, ready }

/// The inbox, sorted into categories, plus the user's selection.
class InboxStore extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  InboxStore({SmsPlatform platform = const SmsPlatform()}) : _platform = platform;

  final SmsPlatform _platform;

  static const _prevPackageKey = 'previous_sms_package';
  static const _prevLabelKey = 'previous_sms_label';

  InboxStatus status = InboxStatus.loading;
  String? error;
  bool deleting = false;

  List<SmsMessage> _all = const [];
  List<SmsMessage> _messages = const [];
  Map<SmsCategory, List<SmsMessage>> _byCategory = const {};
  final Set<int> _selected = {};
  MessageFilter _filter = MessageFilter.all;

  /// What the last clean removed. Null until a clean finishes (or dismissed).
  CleanSummary? lastSummary;

  MessageFilter get filter => _filter;

  /// Every message on the phone (SMS and MMS, all boxes), ignoring the filter.
  List<SmsMessage> get allMessages => _all;

  /// Shows only messages matching [f]. The selection is cleared so nothing
  /// hidden can be deleted.
  void setFilter(MessageFilter f) {
    if (f == _filter) return;
    _filter = f;
    _selected.clear();
    _applyFilter();
    notifyListeners();
  }

  void dismissSummary() {
    lastSummary = null;
    notifyListeners();
  }

  /// Current holder of the default SMS role.
  DefaultSmsApp defaultApp = const DefaultSmsApp();

  /// Role and Android version as last reported by the phone.
  SmsRoleSnapshot role = const SmsRoleSnapshot();
  SmsRoleUiState get roleUi => roleUiState(role);

  /// True after a permission or role request was refused in a way that looks
  /// like Android's "Restricted settings" (see [looksRestricted]).
  bool restrictedSuspected = false;

  void dismissRestricted() {
    restrictedSuspected = false;
    notifyListeners();
  }

  /// The messaging app that was the default before Sift took over.
  String? previousPackage;
  String? previousLabel;

  /// The messages that match the filter.
  List<SmsMessage> get messages => _messages;
  int get total => _messages.length;
  Set<int> get selected => _selected;
  int get selectedCount => _selected.length;

  /// Categories that have messages, in display order.
  List<SmsCategory> get categories => [
    for (final c in SmsCategory.values)
      if ((_byCategory[c]?.isNotEmpty ?? false)) c,
  ];

  List<SmsMessage> inCategory(SmsCategory c) => _byCategory[c] ?? const [];

  int selectedIn(SmsCategory c) => inCategory(c).where((m) => _selected.contains(m.key)).length;

  /// true = all, false = none, null = some. For tristate checkboxes.
  bool? selectionState(Iterable<SmsMessage> list) {
    var any = false, all = true;
    for (final m in list) {
      if (_selected.contains(m.key)) {
        any = true;
      } else {
        all = false;
      }
    }
    if (!any) return false;
    return all ? true : null;
  }

  String get previousName => previousLabel ?? 'your messaging app';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    previousPackage = prefs.getString(_prevPackageKey);
    previousLabel = prefs.getString(_prevLabelKey);
    await refreshDefaultApp();
    final perm = await Permission.sms.status;
    if (perm.isGranted) {
      await load();
    } else {
      status = perm.isPermanentlyDenied ? InboxStatus.permanentlyDenied : InboxStatus.needsPermission;
      notifyListeners();
    }
  }

  Future<void> requestPermission() async {
    final watch = Stopwatch()..start();
    final result = await Permission.sms.request();
    watch.stop();
    if (result.isGranted) {
      restrictedSuspected = false;
      await load();
    } else {
      // A prompt that vanishes at once on Android 13+ is Restricted settings.
      final sdk = role.sdk;
      if (looksRestricted(sdk: sdk, outcome: RequestOutcome(granted: false, elapsedMs: watch.elapsedMilliseconds))) {
        restrictedSuspected = true;
      }
      status = result.isPermanentlyDenied ? InboxStatus.permanentlyDenied : InboxStatus.needsPermission;
      notifyListeners();
    }
  }

  Future<void> load() async {
    status = InboxStatus.loading;
    notifyListeners();
    try {
      _setMessages(await _platform.loadMessages());
      status = InboxStatus.ready;
      error = null;
    } on PlatformException catch (e) {
      final denied = e.code == 'security' || e.code == 'no_permission';
      status = denied ? InboxStatus.needsPermission : InboxStatus.error;
      if (denied && role.sdk >= restrictedSettingsMinSdk) restrictedSuspected = true;
      error = e.message;
    }
    notifyListeners();
  }

  /// Re-queries the phone. Returns false if that failed.
  Future<bool> _reloadQuietly() async {
    try {
      _setMessages(await _platform.loadMessages());
      return true;
    } on PlatformException catch (e) {
      error = e.message;
      return false;
    }
  }

  void _setMessages(List<SmsMessage> list) {
    _all = list;
    _applyFilter();
    final keys = {for (final m in list) m.key};
    _selected.retainWhere(keys.contains);
  }

  void _applyFilter() {
    final list = [for (final m in _all) if (_filter.matches(m)) m];
    _messages = list;
    final groups = <SmsCategory, List<SmsMessage>>{};
    for (final m in list) {
      (groups[m.category] ??= []).add(m);
    }
    _byCategory = groups;
  }

  Future<DefaultSmsApp> refreshDefaultApp() async {
    try {
      role = await _platform.roleState();
      defaultApp = DefaultSmsApp(package: role.defaultPackage, label: role.defaultLabel, isSelf: role.roleHeld);
    } on PlatformException {
      defaultApp = const DefaultSmsApp();
    } on MissingPluginException {
      defaultApp = const DefaultSmsApp();
    }
    notifyListeners();
    return defaultApp;
  }

  /// Toggles one message by [SmsMessage.key].
  void toggle(int key) {
    _selected.contains(key) ? _selected.remove(key) : _selected.add(key);
    notifyListeners();
  }

  /// Selects every message in [list], or clears them all if all are already selected.
  void toggleAll(Iterable<SmsMessage> list) {
    final keys = list.map((m) => m.key).toList();
    if (selectionState(list) == true) {
      _selected.removeAll(keys);
    } else {
      _selected.addAll(keys);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  /// Asks Android to make Sift the default SMS app, remembering the old one.
  Future<bool> becomeDefault() async {
    final current = await refreshDefaultApp();
    if (current.isSelf) return true;
    if (current.package != null) {
      previousPackage = current.package;
      previousLabel = current.label;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prevPackageKey, current.package!);
      if (current.label != null) await prefs.setString(_prevLabelKey, current.label!);
    }
    final outcome = await _platform.requestDefaultSmsApp();
    await refreshDefaultApp();
    final ok = outcome.granted || defaultApp.isSelf;
    if (ok) {
      restrictedSuspected = false;
    } else if (looksRestricted(sdk: role.sdk, outcome: outcome)) {
      restrictedSuspected = true;
    }
    notifyListeners();
    return ok;
  }

  /// Opens Sift's page in Android Settings (where "Allow restricted settings" lives).
  Future<void> openAppDetails() => _platform.openAppDetails();

  /// Retry after the user allowed restricted settings: ask for the permission again.
  Future<void> retryAfterRestricted() async {
    restrictedSuspected = false;
    notifyListeners();
    if (status == InboxStatus.ready) {
      await refreshDefaultApp();
    } else {
      await requestPermission();
    }
  }

  /// Hands the default SMS role back to [previousPackage].
  Future<void> restoreDefault() => _platform.restoreDefaultSmsApp(previousPackage);

  /// Opens Google Messages (or the default SMS app). See [SmsPlatform.openGoogleMessages].
  Future<String> openGoogleMessages() => _platform.openGoogleMessages();

  /// Deletes the messages with these [SmsMessage.key]s by id (SMS through
  /// content://sms, MMS through content://mms), then re-queries.
  Future<CleanSummary> delete(Iterable<int> keys) =>
      runPlan(planDelete(_all, keys.toSet()));

  /// Deletes every message in thread [threadId] (SMS and MMS) as one conversation.
  Future<CleanSummary> deleteConversation(int threadId) {
    final keys = {for (final m in _all) if (m.threadId == threadId) m.key};
    return runPlan(planDelete(_all, keys, useThreads: true));
  }

  /// Deletes everything the filter shows: threads where every message is
  /// shown go as whole conversations, the rest by id.
  Future<CleanSummary> deleteShown() =>
      runPlan(planDelete(_all, {for (final m in _messages) m.key}, useThreads: true));

  /// Runs [plan], re-queries the phone, and records the [lastSummary].
  Future<CleanSummary> runPlan(DeletePlan plan) async {
    deleting = true;
    notifyListeners();
    try {
      final before = _all;
      final DeleteOutcome outcome;
      try {
        outcome = await executeDelete(_platform, plan);
      } on SmsSecurityException {
        await _reloadQuietly();
        rethrow;
      }
      final reloaded = await _reloadQuietly();
      final summary = summarize(
        plan,
        outcome,
        allBefore: before,
        remaining: reloaded ? {for (final m in _all) m.key} : null,
      );
      if (summary.removed > 0) lastSummary = summary;
      return summary;
    } finally {
      deleting = false;
      notifyListeners();
    }
  }
}
