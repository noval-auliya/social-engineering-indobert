/// Pesan WhatsApp yang ditangkap dari notifikasi oleh listener native Android.
class CapturedMessage {
  final String sender;
  final String conversation;
  final String text;
  final DateTime receivedAt;

  const CapturedMessage({
    required this.sender,
    required this.conversation,
    required this.text,
    required this.receivedAt,
  });

  factory CapturedMessage.fromMap(Map<Object?, Object?> map) {
    return CapturedMessage(
      sender: map['sender'] as String? ?? '',
      conversation: map['conversation'] as String? ?? '',
      text: map['text'] as String? ?? '',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['timestamp'] as num?)?.toInt() ?? 0),
    );
  }

  /// Label pengirim untuk riwayat, mis. "Budi" atau "Budi @ Grup Keluarga".
  String get senderLabel {
    if (conversation.isEmpty || conversation == sender) return sender;
    return '$sender @ $conversation';
  }
}
