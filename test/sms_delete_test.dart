import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sift/sms/inbox_store.dart';
import 'package:sift/sms/role_state.dart';
import 'package:sift/sms/sms_delete.dart';
import 'package:sift/sms/sms_message.dart';
import 'package:sift/sms/sms_platform.dart';

SmsMessage msg(int id, {MessageKind kind = MessageKind.sms, int thread = 1, MessageBox box = MessageBox.received}) =>
    SmsMessage(
      id: id,
      threadId: thread,
      address: 'AX-HDFCBK',
      body: 'msg $id',
      date: DateTime(2026, 1, id.abs() + 1),
      read: true,
      kind: kind,
      box: box,
    );

/// A pretend phone: the content://sms and content://mms tables.
class FakeResolver implements SmsResolverBridge {
  FakeResolver(Iterable<SmsMessage> table, {this.stuck = const {}}) : table = [...table];

  factory FakeResolver.sms(Iterable<int> ids, {Set<int> stuck = const {}}) =>
      FakeResolver([for (final id in ids) msg(id)], stuck: stuck);

  final List<SmsMessage> table;

  /// SMS ids the bulk delete skips (a locked row), but a single delete removes.
  final Set<int> stuck;
  final bulkSizes = <int>[];
  final mmsBulkSizes = <int>[];
  final threadCalls = <List<int>>[];
  int singles = 0;

  Set<int> get rows => {for (final m in table) if (m.kind == MessageKind.sms) m.id};
  Set<int> get mmsRows => {for (final m in table) if (m.kind == MessageKind.mms) m.id};

  int _remove(MessageKind kind, bool Function(SmsMessage) test) {
    final before = table.length;
    table.removeWhere((m) => m.kind == kind && test(m));
    return before - table.length;
  }

  @override
  Future<int> deleteByIds(List<int> ids) async {
    bulkSizes.add(ids.length);
    return _remove(MessageKind.sms, (m) => ids.contains(m.id) && !stuck.contains(m.id));
  }

  @override
  Future<int> deleteById(int id) async {
    singles++;
    return _remove(MessageKind.sms, (m) => m.id == id);
  }

  @override
  Future<int> deleteMmsByIds(List<int> ids) async {
    mmsBulkSizes.add(ids.length);
    return _remove(MessageKind.mms, (m) => ids.contains(m.id));
  }

  @override
  Future<int> deleteMmsById(int id) async => _remove(MessageKind.mms, (m) => m.id == id);

  @override
  Future<int> deleteThreads(List<int> threadIds) async {
    threadCalls.add(threadIds);
    final before = table.length;
    table.removeWhere((m) => threadIds.contains(m.threadId));
    return before - table.length;
  }
}

class FakePlatform extends FakeResolver implements SmsPlatform {
  FakePlatform(super.table, {this.securityError = false});

  final bool securityError;
  int loads = 0;
  SmsRoleSnapshot snapshot = const SmsRoleSnapshot(sdk: 34, roleHeld: true);

  @override
  Future<DefaultSmsApp> defaultSmsApp() async => const DefaultSmsApp(isSelf: true);

  @override
  Future<SmsRoleSnapshot> roleState() async => snapshot;

  @override
  Future<RequestOutcome> requestDefaultSmsApp() async => const RequestOutcome(granted: true);

  @override
  Future<String> restoreDefaultSmsApp(String? package) async => 'settings';

  @override
  Future<void> openAppDetails() async {}

  @override
  Future<String> openGoogleMessages() async => 'google';

  @override
  Future<List<SmsMessage>> loadMessages() async {
    loads++;
    return [...table];
  }

  @override
  Future<int> deleteByIds(List<int> ids) {
    if (securityError) throw const SmsSecurityException('denied');
    return super.deleteByIds(ids);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('deleteSms', () {
    test('counts what the resolver removed', () async {
      final r = FakeResolver.sms(List.generate(10, (i) => i));
      final res = await deleteSms(r, [1, 2, 3]);
      expect((res.requested, res.deleted, res.complete), (3, 3, true));
      expect(r.rows.length, 7);
    });

    test('chunks large selections', () async {
      final r = FakeResolver.sms(List.generate(1000, (i) => i));
      final res = await deleteSms(r, List.generate(1000, (i) => i));
      expect(r.bulkSizes, [400, 400, 200]);
      expect(res.deleted, 1000);
    });

    test('duplicates are counted once', () async {
      final r = FakeResolver.sms([1, 2]);
      final res = await deleteSms(r, [1, 1, 2]);
      expect((res.requested, res.deleted), (2, 2));
    });

    test('a stuck row is retried alone and the total adds up', () async {
      final r = FakeResolver.sms([1, 2, 3, 4], stuck: {3});
      final res = await deleteSms(r, [1, 2, 3, 4]);
      expect(res.deleted, 4);
      expect(r.rows, isEmpty);
      expect(r.singles, 4);
    });

    test('rows that are not there count as failures', () async {
      final r = FakeResolver.sms([1]);
      final res = await deleteSms(r, [1, 99]);
      expect((res.deleted, res.failed, res.complete), (1, 1, false));
    });

    test('a non-default app deletes nothing: reported as 0', () async {
      final r = FakeResolver.sms([1, 2]);
      r.table.clear(); // provider refuses everything
      final res = await deleteSms(r, [1, 2]);
      expect(res.deleted, 0);
    });
  });

  group('per-kind counting', () {
    test('SMS and MMS with the same id are deleted from their own table', () async {
      final r = FakeResolver([msg(5), msg(5, kind: MessageKind.mms), msg(6, kind: MessageKind.mms)]);
      final out = await executeDelete(r, const DeletePlan(smsIds: [5], mmsIds: [5, 6]));
      expect((out.sms.deleted, out.mms.deleted), (1, 2));
      expect(r.table, isEmpty);
    });

    test('MMS delete is chunked like SMS', () async {
      final r = FakeResolver([for (var i = 1; i <= 900; i++) msg(i, kind: MessageKind.mms)]);
      final res = await deleteMms(r, List.generate(900, (i) => i + 1));
      expect(r.mmsBulkSizes, [400, 400, 100]);
      expect(res.deleted, 900);
    });

    test('summary has the exact sentence with per-kind counts', () async {
      final all = [msg(1), msg(2), msg(3, kind: MessageKind.mms)];
      final r = FakeResolver(all);
      final plan = planDelete(all, {1, 2, -3});
      final out = await executeDelete(r, plan);
      final s = summarize(plan, out);
      expect(s.message, 'Removed 2 SMS and 1 MMS. Google Messages may still show RCS chats; see below.');
      expect(s.complete, isTrue);
    });

    test('thread deletes are counted per kind from what is really gone', () async {
      final all = [msg(1), msg(2, kind: MessageKind.mms), msg(3, thread: 2)];
      final r = FakeResolver(all);
      final plan = planDelete(all, {1, -2}, useThreads: true);
      final out = await executeDelete(r, plan);
      final s = summarize(plan, out, allBefore: all, remaining: {for (final m in r.table) m.key});
      expect((s.removedSms, s.removedMms), (1, 1));
      expect(out.threadRows, 2);
    });
  });

  group('InboxStore.delete', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('re-queries the phone after deleting and reports the summary', () async {
      final p = FakePlatform([msg(1), msg(2), msg(3)]);
      final store = InboxStore(platform: p);
      await store.load();
      final res = await store.delete([1, 2]);
      expect(res.removedSms, 2);
      expect(p.loads, 2); // initial load + re-query after the delete
      expect(store.messages.map((m) => m.id), [3]);
      expect(store.deleting, isFalse);
      expect(store.lastSummary?.removed, 2);
    });

    test('SecurityException surfaces and the list is still refreshed', () async {
      final p = FakePlatform([msg(1), msg(2)], securityError: true);
      final store = InboxStore(platform: p);
      await store.load();
      await expectLater(store.delete([1]), throwsA(isA<SmsSecurityException>()));
      expect(p.loads, 2);
      expect(store.deleting, isFalse);
    });

    test('deleteConversation removes SMS and MMS of the thread only', () async {
      final p = FakePlatform([msg(1), msg(2, kind: MessageKind.mms), msg(3, thread: 2)]);
      final store = InboxStore(platform: p);
      await store.load();
      final s = await store.deleteConversation(1);
      expect(p.threadCalls, [
        [1],
      ]);
      expect((s.removedSms, s.removedMms), (1, 1));
      expect(store.allMessages.map((m) => m.id), [3]);
    });

    test('deleteShown uses threads when all selected, ids otherwise', () async {
      final p = FakePlatform([
        msg(1, box: MessageBox.sent),
        msg(2, box: MessageBox.received), // thread 1 is not fully shown
        msg(3, thread: 2, box: MessageBox.sent),
      ]);
      final store = InboxStore(platform: p);
      await store.load();
      store.setFilter(MessageFilter.sent);
      final s = await store.deleteShown();
      expect(p.threadCalls, [
        [2],
      ]);
      expect(s.removedSms, 2);
      expect(store.allMessages.map((m) => m.id), [2]);
    });

    test('changing the filter clears the selection', () async {
      final store = InboxStore(platform: FakePlatform([msg(1), msg(2, kind: MessageKind.mms)]));
      await store.load();
      store.toggle(1);
      store.setFilter(MessageFilter.mms);
      expect(store.selectedCount, 0);
      expect(store.messages.map((m) => m.id), [2]);
    });

    test('role state drives the UI state', () async {
      final p = FakePlatform([msg(1)]);
      final store = InboxStore(platform: p);
      await store.refreshDefaultApp();
      expect(store.roleUi, SmsRoleUiState.defaultApp);
      p.snapshot = const SmsRoleSnapshot(sdk: 34);
      await store.refreshDefaultApp();
      expect(store.roleUi, SmsRoleUiState.notDefault);
      expect(store.defaultApp.isSelf, isFalse);
    });
  });

  test('platform errors keep their message', () {
    expect(const SmsSecurityException('x').toString(), 'x');
    expect(PlatformException(code: 'security', message: 'm').code, 'security');
  });
}
