/// Deleting SMS through a thin bridge to Android's ContentResolver, with exact
/// counting. The bridge is faked in test/sms_delete_test.dart.
abstract class SmsResolverBridge {
  /// `ContentResolver.delete(content://sms, "_id IN (...)")`. Returns rows deleted.
  Future<int> deleteByIds(List<int> ids);

  /// `ContentResolver.delete(content://sms/<id>)`. Returns 0 or 1.
  Future<int> deleteById(int id);
}

/// How a delete went.
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
Future<DeleteResult> deleteSms(SmsResolverBridge bridge, Iterable<int> ids, {int chunkSize = deleteChunkSize}) async {
  final unique = ids.toSet().toList();
  var deleted = 0;
  for (var i = 0; i < unique.length; i += chunkSize) {
    final end = i + chunkSize > unique.length ? unique.length : i + chunkSize;
    final chunk = unique.sublist(i, end);
    final n = await bridge.deleteByIds(chunk);
    if (n >= chunk.length) {
      deleted += chunk.length;
      continue;
    }
    // Some rows were not removed (or were already gone): retry one by one.
    // Rows the first call removed return 0 now, so the counts add up.
    var got = 0;
    for (final id in chunk) {
      got += await bridge.deleteById(id);
    }
    deleted += n + got;
  }
  return DeleteResult(requested: unique.length, deleted: deleted);
}
