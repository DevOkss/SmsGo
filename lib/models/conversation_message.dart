class ConversationMessage {
  final int? id;
  final int conversationId;
  final int? sessionId;
  final String direction; // 'in' or 'out'
  final String message;

  /// Outgoing message state: 'sending', 'sent', 'failed'.
  /// Incoming messages have empty status (no status icon shown).
  final String status;

  /// SIM slot used for outgoing messages (e.g., 'SIM 1', 'SIM 2').
  final String? simSlot;

  final String createdAt;

  ConversationMessage({
    this.id,
    required this.conversationId,
    this.sessionId,
    required this.direction,
    required this.message,
    required this.createdAt,
    this.status = 'sent',
    this.simSlot,
  });


  factory ConversationMessage.fromMap(Map<String, dynamic> m) => ConversationMessage(
        id: m['id'] as int?,
        conversationId: m['conversation_id'] as int,
        sessionId: m['session_id'] as int?,
        direction: m['direction'] as String,
        message: m['message'] as String,
        status: (m['status'] as String?) ?? 'sent',
        simSlot: m['sim_slot'] as String?,
        createdAt: m['created_at'] as String,
      );


  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'conversation_id': conversationId,
        'session_id': sessionId,
        'direction': direction,
        'message': message,
        'status': status,
        'sim_slot': simSlot,
        'created_at': createdAt,
      };

}
