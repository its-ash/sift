import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sift/sms/inbox_store.dart';
import 'package:sift/sms/role_state.dart';
import 'package:sift/sms/sms_delete.dart';
import 'package:sift/sms/sms_message.dart';
import 'package:sift/sms/sms_platform.dart';

/// A pretend content://sms table.
class FakeResolver implements SmsResolverBridge {
  FakeResolver(Iterable<int> rows, {this.stuck = const {}}) : rows = {...rows};

  final Set<int> rows;

  /// Ids the bulk delete skips (a locked row), but a single delete removes.
  final Set<int> stuck;
  final bulkSizes = <int>[];
  int singles = 0;

  @override
  Future<int> deleteByIds(List<int> ids) async {
    bulkSizes.add(ids.length);
    var n = 0;
    for (final id in ids) {
      if (stuck.contains(id)) continue;
      if (rows.remove(id)) n++;
    }
    return n;
  }

  @override
  Future<int> deleteById(int id) async {
    singles++;
    return rows.remove(id) ? 1 : 0;
  }
}

class FakePlatform extends FakeResolver implements SmsPlatform {
  FakePlatform(super.rows, {this.securityError = false});

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
  Future<List<SmsMessage>> loadInbox() async {
    loads++;
    return [
      for (final id in rows)
        SmsMessage(id: id, threadId: 1, address: 'AX-HDFCBK', body: 'msg $id', date: DateTime(2026), read: true),
    ];
  }

  @override
  Future<int> deleteByIds(List<int> ids) {
    if (securityError) throw const SmsSecurityException('denied');
    return super.deleteByIds(ids);
  }

  @override
  Future<int> deleteThreads(List<int> threadIds) async => 0;

  @override
  Future<DeleteResult> deleteMessages(Iterable<int> ids) => deleteSms(this, ids);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('deleteSms', () {
    test('counts what the resolver removed', () async {
      final r = FakeResolver(List.generate(10, (i) => i));
      final res = await deleteSms(r, [1, 2, 3]);
      expect((res.requested, res.deleted, res.complete), (3, 3, true));
      expect(r.rows.length, 7);
    });

    test('chunks large selections', () async {
      final r = FakeResolver(List.generate(1000, (i) => i));
      final res = await deleteSms(r, List.generate(1000, (i) => i));
      expect(r.bulkSizes, [400, 400, 200]);
      expect(res.deleted, 1000);
    });

    test('duplicates are counted once', () async {
      final r = FakeResolver([1, 2]);
      final res = await deleteSms(r, [1, 1, 2]);
      expect((res.requested, res.deleted), (2, 2));
    });

    test('a stuck row is retried alone and the total adds up', () async {
      final r = FakeResolver([1, 2, 3, 4], stuck: {3});
      final res = await deleteSms(r, [1, 2, 3, 4]);
      expect(res.deleted, 4);
      expect(r.rows, isEmpty);
      expect(r.singles, 4);
    });

    test('rows that are not there count as failures', () async {
      final r = FakeResolver([1]);
      final res = await deleteSms(r, [1, 99]);
      expect((res.deleted, res.failed, res.complete), (1, 1, false));
    });

    test('a non-default app deletes nothing: reported as 0', () async {
      final r = FakeResolver([1, 2], stuck: {1, 2});
      r.rows.clear(); // provider refuses everything
      final res = await deleteSms(r, [1, 2]);
      expect(res.deleted, 0);
    });
  });

  group('InboxStore.delete', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('re-queries the inbox after deleting', () async {
      final p = FakePlatform([1, 2, 3]);
      final store = InboxStore(platform: p);
      final res = await store.delete([1, 2]);
      expect(res.deleted, 2);
      expect(p.loads, 1);
      expect(store.messages.map((m) => m.id), [3]);
      expect(store.deleting, isFalse);
    });

    test('SecurityException surfaces and the list is still refreshed', () async {
      final p = FakePlatform([1, 2], securityError: true);
      final store = InboxStore(platform: p);
      await expectLater(store.delete([1]), throwsA(isA<SmsSecurityException>()));
      expect(p.loads, 1);
      expect(store.deleting, isFalse);
    });

    test('role state drives the UI state', () async {
      final p = FakePlatform([1]);
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
