class MessageThread {
  MessageThread({
    required this.companionId,
    required this.displayName,
    required this.photoUrl,
    this.lastPreview,
    required this.updatedAtMs,
  });

  final int companionId;
  final String displayName;
  final String photoUrl;
  final String? lastPreview;
  final int updatedAtMs;

  factory MessageThread.fromJson(Map<String, dynamic> j) {
    return MessageThread(
      companionId: (j['companionId'] as num).toInt(),
      displayName: j['displayName'] as String,
      photoUrl: j['photoUrl'] as String,
      lastPreview: j['lastPreview'] as String?,
      updatedAtMs: (j['updatedAtMs'] as num).toInt(),
    );
  }
}
