class ChatMessage {
  ChatMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.sentAt,
  });

  final int id;
  final String sender;
  final String body;
  final DateTime sentAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      sender: json['sender'] as String,
      body: json['body'] as String,
      sentAt: DateTime.parse(json['sentAt'] as String),
    );
  }

  bool get isCliente => sender == 'cliente';
}
