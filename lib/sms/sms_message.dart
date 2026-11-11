import 'categorizer.dart';

/// Which Android table a message lives in.
enum MessageKind {
  sms('SMS'),
  mms('MMS');

  const MessageKind(this.label);
  final String label;
}

/// Where a message sits: received, sent, a draft, or anything else (outbox,
/// failed, queued).
enum MessageBox {
  received('Received'),
  sent('Sent'),
  draft('Draft'),
  other('Other');

  const MessageBox(this.label);
  final String label;

  /// Maps `Telephony.Sms.TYPE` / `Telephony.Mms.MESSAGE_BOX` (1 inbox, 2 sent,
  /// 3 draft, 4 outbox, 5 failed, 6 queued).
  static MessageBox fromType(int type) => switch (type) {
    1 => received,
    2 => sent,
    3 => draft,
    _ => other,
  };
}

/// The list filter on the home screen.
enum MessageFilter {
  all('All'),
  received('Received'),
  sent('Sent'),
  mms('MMS');

  const MessageFilter(this.label);
  final String label;

  bool matches(SmsMessage m) => switch (this) {
    all => true,
    received => m.box == MessageBox.received,
    sent => m.box == MessageBox.sent,
    mms => m.kind == MessageKind.mms,
  };
}

/// Shown for an MMS that has no text part.
const mediaMessageText = 'Picture/media message';

/// One message from the phone's SMS or MMS store.
class SmsMessage {
  SmsMessage({
    required this.id,
    required this.threadId,
    required this.address,
    required this.body,
    required this.date,
    required this.read,
    this.kind = MessageKind.sms,
    this.box = MessageBox.received,
  }) : category = SmsCategorizer.categorize(address, body);

  factory SmsMessage.fromMap(Map<Object?, Object?> map) {
    final kind = map['kind'] == 'mms' ? MessageKind.mms : MessageKind.sms;
    final text = (map['body'] as String? ?? '').trim();
    return SmsMessage(
      id: (map['id'] as num).toInt(),
      threadId: (map['threadId'] as num? ?? 0).toInt(),
      address: map['address'] as String? ?? '',
      body: kind == MessageKind.mms && text.isEmpty ? mediaMessageText : (map['body'] as String? ?? ''),
      date: DateTime.fromMillisecondsSinceEpoch((map['date'] as num? ?? 0).toInt()),
      read: map['read'] as bool? ?? true,
      kind: kind,
      box: MessageBox.fromType((map['box'] as num? ?? 1).toInt()),
    );
  }

  final int id;
  final int threadId;
  final String address;
  final String body;
  final DateTime date;
  final bool read;
  final MessageKind kind;
  final MessageBox box;
  final SmsCategory category;

  /// SMS and MMS ids come from different tables and can be equal, so the
  /// selection uses this key: the id for SMS, the negated id for MMS.
  int get key => kind == MessageKind.mms ? -id : id;

  /// Short chip text such as "MMS · Sent".
  String get chip => '${kind.label} · ${box.label}';

  String get sender => address.isEmpty ? 'Unknown sender' : address;
}

/// Turns the rows from the platform (SMS and MMS together) into messages,
/// newest first.
List<SmsMessage> parseMessages(Iterable<Map<Object?, Object?>> rows) {
  final list = [for (final r in rows) SmsMessage.fromMap(r)];
  list.sort((a, b) => b.date.compareTo(a.date));
  return list;
}
