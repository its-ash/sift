import 'categorizer.dart';

/// One SMS from the phone's inbox.
class SmsMessage {
  SmsMessage({
    required this.id,
    required this.threadId,
    required this.address,
    required this.body,
    required this.date,
    required this.read,
  }) : category = SmsCategorizer.categorize(address, body);

  factory SmsMessage.fromMap(Map<Object?, Object?> map) => SmsMessage(
    id: (map['id'] as num).toInt(),
    threadId: (map['threadId'] as num? ?? 0).toInt(),
    address: map['address'] as String? ?? '',
    body: map['body'] as String? ?? '',
    date: DateTime.fromMillisecondsSinceEpoch((map['date'] as num? ?? 0).toInt()),
    read: map['read'] as bool? ?? true,
  );

  final int id;
  final int threadId;
  final String address;
  final String body;
  final DateTime date;
  final bool read;
  final SmsCategory category;

  String get sender => address.isEmpty ? 'Unknown sender' : address;
}
