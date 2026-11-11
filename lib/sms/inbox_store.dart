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

  List<SmsMessage> _messages = const [];
  Map<SmsCategory, List<SmsMessage>> _byCategory = const {};
  final Set<int> _selected = {};

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

  int selectedIn(SmsCategory c) => inCategory(c).where((m) => _selected.contains(m.id)).length;

  /// true = all, false = none, null = some. For tristate checkboxes.
  bool? selectionState(Iterable<SmsMessage> list) {
    var any = false, all = true;
    for (final m in list) {
      if (_selected.contains(m.id)) {
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
      _setMessages(await _platform.loadInbox());
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

  Future<void> _reloadQuietly() async {
    try {
      _setMessages(await _platform.loadInbox());
    } on PlatformException catch (e) {
      error = e.message;
    }
  }

  void _setMessages(List<SmsMessage> list) {
    _messages = list;
    final groups = <SmsCategory, List<SmsMessage>>{};
    for (final m in list) {
      (groups[m.category] ??= []).add(m);
    }
    _byCategory = groups;
    final ids = {for (final m in list) m.id};
    _selected.retainWhere(ids.contains);
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

  void toggle(int id) {
    _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
    notifyListeners();
  }

  /// Selects every message in [list], or clears them all if all are already selected.
  void toggleAll(Iterable<SmsMessage> list) {
    final ids = list.map((m) => m.id).toList();
    if (selectionState(list) == true) {
      _selected.removeAll(ids);
    } else {
      _selected.addAll(ids);
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

  /// Deletes [ids] from the phone, then re-queries the inbox so the list is
  /// what is really left. Returns how many rows Android reported deleting.
  Future<DeleteResult> delete(Iterable<int> ids) async {
    deleting = true;
    notifyListeners();
    try {
      DeleteResult result;
      try {
        result = await _platform.deleteMessages(ids);
      } on SmsSecurityException {
        await _reloadQuietly();
        rethrow;
      }
      await _reloadQuietly();
      return result;
    } finally {
      deleting = false;
      notifyListeners();
    }
  }
}
