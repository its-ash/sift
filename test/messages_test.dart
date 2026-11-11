import 'package:flutter_test/flutter_test.dart';
import 'package:sift/sms/categorizer.dart';
import 'package:sift/sms/sms_delete.dart';
import 'package:sift/sms/sms_message.dart';

/// Rows as MainActivity.loadMessages() returns them (SMS and MMS together).
final rows = <Map<Object?, Object?>>[
  {'kind': 'sms', 'id': 1, 'threadId': 10, 'address': 'AX-HDFCBK', 'body': 'Your OTP is 123456', 'date': 1000, 'read': true, 'box': 1},
  {'kind': 'sms', 'id': 2, 'threadId': 11, 'address': '+919876543210', 'body': 'On my way', 'date': 3000, 'read': true, 'box': 2},
  {'kind': 'sms', 'id': 3, 'threadId': 11, 'address': '+919876543210', 'body': 'draft text', 'date': 2500, 'read': true, 'box': 3},
  {'kind': 'sms', 'id': 4, 'threadId': 12, 'address': '+919876543211', 'body': 'failed one', 'date': 500, 'read': true, 'box': 5},
  {'kind': 'mms', 'id': 1, 'threadId': 11, 'address': '+919876543210', 'body': '', 'date': 4000, 'read': false, 'box': 1},
  {'kind': 'mms', 'id': 2, 'threadId': 13, 'address': '+919876543212', 'body': 'look at this', 'date': 2000, 'read': true, 'box': 2},
];

void main() {
  group('parseMessages', () {
    final list = parseMessages(rows);

    test('merges SMS and MMS, newest first', () {
      expect(list.map((m) => '${m.kind.name}${m.id}'), ['mms1', 'sms2', 'sms3', 'mms2', 'sms1', 'sms4']);
    });

    test('maps types to boxes', () {
      final byKey = {for (final m in list) m.key: m};
      expect(byKey[1]!.box, MessageBox.received);
      expect(byKey[2]!.box, MessageBox.sent);
      expect(byKey[3]!.box, MessageBox.draft);
      expect(byKey[4]!.box, MessageBox.other); // failed
      expect(byKey[-2]!.box, MessageBox.sent);
    });

    test('MMS without text is a media message', () {
      final m = list.firstWhere((m) => m.kind == MessageKind.mms && m.id == 1);
      expect(m.body, mediaMessageText);
      expect(m.chip, 'MMS · Received');
    });

    test('SMS and MMS with the same id have different keys', () {
      final sms = list.firstWhere((m) => m.kind == MessageKind.sms && m.id == 1);
      final mms = list.firstWhere((m) => m.kind == MessageKind.mms && m.id == 1);
      expect(sms.key, isNot(mms.key));
    });

    test('categorisation works on the combined set', () {
      final otp = list.firstWhere((m) => m.kind == MessageKind.sms && m.id == 1);
      expect(otp.category, SmsCategory.otp);
      final text = list.firstWhere((m) => m.kind == MessageKind.mms && m.id == 2);
      expect(text.category, SmsCategory.personal);
    });

    test('filters', () {
      List<String> ids(MessageFilter f) => [for (final m in list.where(f.matches)) '${m.kind.name}${m.id}'];
      expect(ids(MessageFilter.all).length, 6);
      expect(ids(MessageFilter.received), ['mms1', 'sms1']);
      expect(ids(MessageFilter.sent), ['sms2', 'mms2']);
      expect(ids(MessageFilter.mms), ['mms1', 'mms2']);
    });
  });

  group('planDelete', () {
    final all = parseMessages(rows);
    Set<int> keys(Iterable<SmsMessage> l) => {for (final m in l) m.key};

    test('by id: SMS and MMS ids are split by kind', () {
      final plan = planDelete(all, {1, -1, -2});
      expect(plan.threadIds, isEmpty);
      expect(plan.smsIds, [1]);
      expect(plan.mmsIds, unorderedEquals([1, 2]));
    });

    test('a thread with every message selected is deleted as a whole', () {
      // Thread 11 holds sms 2, sms 3 and mms 1.
      final plan = planDelete(all, {2, 3, -1}, useThreads: true);
      expect(plan.threadIds, [11]);
      expect((plan.threadSms, plan.threadMms), (2, 1));
      expect(plan.smsIds, isEmpty);
      expect(plan.mmsIds, isEmpty);
    });

    test('a partly selected thread falls back to ids', () {
      final plan = planDelete(all, {2, -1}, useThreads: true);
      expect(plan.threadIds, isEmpty);
      expect(plan.smsIds, [2]);
      expect(plan.mmsIds, [1]);
    });

    test('mixed: whole threads plus ids', () {
      final plan = planDelete(all, {...keys(all.where((m) => m.threadId == 13)), 2}, useThreads: true);
      expect(plan.threadIds, [13]);
      expect(plan.smsIds, [2]); // thread 11 is only partly selected
      expect(plan.requested, 2);
    });

    test('without useThreads nothing is deleted as a thread', () {
      final plan = planDelete(all, keys(all));
      expect(plan.threadIds, isEmpty);
      expect(plan.requestedSms + plan.requestedMms, 6);
    });

    test('messages without a thread are always deleted by id', () {
      final loose = [
        SmsMessage(id: 9, threadId: 0, address: 'x', body: 'y', date: DateTime(2026), read: true),
      ];
      final plan = planDelete(loose, {9}, useThreads: true);
      expect(plan.threadIds, isEmpty);
      expect(plan.smsIds, [9]);
    });
  });
}
