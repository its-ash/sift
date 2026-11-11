import 'sms_message.dart';

/// Deleting messages through a thin bridge to Android's ContentResolver, with
/// exact counting. The bridge is faked in test/sms_delete_test.dart.
abstract class SmsResolverBridge {
  /// `ContentResolver.delete(content://sms, "_id IN (...)")`. Returns rows deleted.
  Future<int> deleteByIds(List<int> ids);

  /// `ContentResolver.delete(content://sms/<id>)`. Returns 0 or 1.
  Future<int> deleteById(int id);

  /// `ContentResolver.delete(content://mms, "_id IN (...)")`. Returns rows deleted.
  Future<int> deleteMmsByIds(List<int> ids);

  /// `ContentResolver.delete(content://mms/<id>)`. Returns 0 or 1.
  Future<int> deleteMmsById(int id);

  /// `content://mms-sms/conversations/<threadId>`: SMS and MMS of whole threads.
  /// Returns rows deleted.
  Future<int> deleteThreads(List<int> threadIds);
}

/// How a delete of one kind went.
class DeleteResult {
  const DeleteResult({required this.requested, required this.deleted});

  final int requested;
  final int deleted;

  int get failed => requested - deleted;
  bool get complete => deleted >= requested;
}

const deleteChunkSize = 400;

/// Deletes [ids] in chunks so huge selections stay under SQLite's limits. If a
/// chunk removes fewer rows than asked, each of its ids is retried alone, so
/// one bad row cannot hide the rest. The count is what Android reported.
Future<DeleteResult> deleteChunked(
  Future<int> Function(List<int> ids) many,
  Future<int> Function(int id) one,
  Iterable<int> ids, {
  int chunkSize = deleteChunkSize,
}) async {
  final unique = ids.toSet().toList();
  var deleted = 0;
  for (var i = 0; i < unique.length; i += chunkSize) {
    final end = i + chunkSize > unique.length ? unique.length : i + chunkSize;
    final chunk = unique.sublist(i, end);
    final n = await many(chunk);
    if (n >= chunk.length) {
      deleted += chunk.length;
      continue;
    }
    // Some rows were not removed (or were already gone): retry one by one.
    // Rows the first call removed return 0 now, so the counts add up.
    var got = 0;
    for (final id in chunk) {
      got += await one(id);
    }
    deleted += n + got;
  }
  return DeleteResult(requested: unique.length, deleted: deleted);
}

/// SMS ids through `content://sms`.
Future<DeleteResult> deleteSms(SmsResolverBridge bridge, Iterable<int> ids, {int chunkSize = deleteChunkSize}) =>
    deleteChunked(bridge.deleteByIds, bridge.deleteById, ids, chunkSize: chunkSize);

/// MMS ids through `content://mms`.
Future<DeleteResult> deleteMms(SmsResolverBridge bridge, Iterable<int> ids, {int chunkSize = deleteChunkSize}) =>
    deleteChunked(bridge.deleteMmsByIds, bridge.deleteMmsById, ids, chunkSize: chunkSize);

/// What to delete: whole threads, plus single messages from the other threads.
class DeletePlan {
  const DeletePlan({
    this.threadIds = const [],
    this.smsIds = const [],
    this.mmsIds = const [],
    this.threadSms = 0,
    this.threadMms = 0,
  });

  /// Threads where every message is selected (deleted as a whole).
  final List<int> threadIds;

  /// SMS / MMS ids deleted one by one (in chunks).
  final List<int> smsIds;
  final List<int> mmsIds;

  /// How many SMS / MMS the [threadIds] threads hold.
  final int threadSms;
  final int threadMms;

  int get requestedSms => smsIds.length + threadSms;
  int get requestedMms => mmsIds.length + threadMms;
  int get requested => requestedSms + requestedMms;
  bool get isEmpty => requested == 0;
}

/// Splits the [selected] message keys ([SmsMessage.key]) into a [DeletePlan].
///
/// With [useThreads], a thread where every message in [all] is selected is
/// deleted as a whole conversation; everything else is deleted by id. Without
/// it, everything is deleted by id.
DeletePlan planDelete(Iterable<SmsMessage> all, Set<int> selected, {bool useThreads = false}) {
  final byThread = <int, List<SmsMessage>>{};
  for (final m in all) {
    if (m.threadId > 0) (byThread[m.threadId] ??= []).add(m);
  }
  final wholeThreads = <int>{};
  if (useThreads) {
    byThread.forEach((id, list) {
      if (list.every((m) => selected.contains(m.key))) wholeThreads.add(id);
    });
  }
  final sms = <int>[], mms = <int>[];
  var threadSms = 0, threadMms = 0;
  for (final m in all) {
    if (!selected.contains(m.key)) continue;
    if (wholeThreads.contains(m.threadId)) {
      m.kind == MessageKind.mms ? threadMms++ : threadSms++;
    } else {
      (m.kind == MessageKind.mms ? mms : sms).add(m.id);
    }
  }
  return DeletePlan(
    threadIds: wholeThreads.toList(),
    smsIds: sms,
    mmsIds: mms,
    threadSms: threadSms,
    threadMms: threadMms,
  );
}

/// What the resolver reported for a [DeletePlan].
class DeleteOutcome {
  const DeleteOutcome({required this.sms, required this.mms, required this.threadRows});

  final DeleteResult sms;
  final DeleteResult mms;

  /// Rows Android reported removing through thread deletes (SMS + MMS).
  final int threadRows;
}

/// Runs [plan]: threads first, then SMS ids, then MMS ids.
Future<DeleteOutcome> executeDelete(SmsResolverBridge bridge, DeletePlan plan) async {
  final rows = plan.threadIds.isEmpty ? 0 : await bridge.deleteThreads(plan.threadIds);
  final sms = await deleteSms(bridge, plan.smsIds);
  final mms = await deleteMms(bridge, plan.mmsIds);
  return DeleteOutcome(sms: sms, mms: mms, threadRows: rows);
}

/// What a clean achieved, per kind.
class CleanSummary {
  const CleanSummary({
    required this.removedSms,
    required this.removedMms,
    required this.requestedSms,
    required this.requestedMms,
  });

  final int removedSms;
  final int removedMms;
  final int requestedSms;
  final int requestedMms;

  int get removed => removedSms + removedMms;
  int get requested => requestedSms + requestedMms;
  int get failed => requested - removed;
  bool get complete => removed >= requested;

  String get message =>
      'Removed $removedSms SMS and $removedMms MMS. Google Messages may still show RCS chats; see below.';
}

/// Builds the summary. Id deletes use the resolver's own counts. Threads are
/// counted from what is really gone after the re-query: [remaining] holds the
/// keys still on the phone ([allBefore] the list before the delete). When the
/// re-query failed (null), the thread row count is split SMS first.
CleanSummary summarize(
  DeletePlan plan,
  DeleteOutcome outcome, {
  Iterable<SmsMessage>? allBefore,
  Set<int>? remaining,
}) {
  var threadSmsGone = 0, threadMmsGone = 0;
  if (plan.threadIds.isNotEmpty) {
    if (allBefore != null && remaining != null) {
      final threads = plan.threadIds.toSet();
      for (final m in allBefore) {
        if (!threads.contains(m.threadId) || remaining.contains(m.key)) continue;
        m.kind == MessageKind.mms ? threadMmsGone++ : threadSmsGone++;
      }
    } else {
      threadSmsGone = outcome.threadRows < plan.threadSms ? outcome.threadRows : plan.threadSms;
      final left = outcome.threadRows - threadSmsGone;
      threadMmsGone = left < plan.threadMms ? left : plan.threadMms;
    }
  }
  return CleanSummary(
    removedSms: outcome.sms.deleted + threadSmsGone,
    removedMms: outcome.mms.deleted + threadMmsGone,
    requestedSms: plan.requestedSms,
    requestedMms: plan.requestedMms,
  );
}
