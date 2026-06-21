class Conversation {
  final int? id;
  final int? sessionId;
  final int? campaignId;
  final int? leadId;
  final String phoneNumber;
  final String? lastMessage;
  final bool replied;
  final bool unread;
  final String createdAt;

  /// Extra fields from joined queries (active send conversations)
  final String? lastActivity;
  final String? outgoingStatus;
  final String? lastDirection;

  Conversation({
    this.id,
    this.sessionId,
    this.campaignId,
    this.leadId,
    required this.phoneNumber,
    this.lastMessage,
    this.replied = false,
    this.unread = false,
    required this.createdAt,
    this.lastActivity,
    this.outgoingStatus,
    this.lastDirection,
  });

  factory Conversation.fromMap(Map<String, dynamic> m) => Conversation(
        id: m['id'] as int?,
        sessionId: m['session_id'] as int?,
        campaignId: m['campaign_id'] as int?,
        leadId: m['lead_id'] as int?,
        phoneNumber: m['phone_number'] as String,
        lastMessage: m['last_message'] as String?,
        replied: (m['replied'] as int? ?? 0) == 1,
        unread: (m['unread'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as String,
        lastActivity: m['last_activity'] as String?,
        outgoingStatus: m['outgoing_status'] as String?,
        lastDirection: m['last_direction'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'campaign_id': campaignId,
        'lead_id': leadId,
        'phone_number': phoneNumber,
        'last_message': lastMessage,
        'replied': replied ? 1 : 0,
        'unread': unread ? 1 : 0,
        'created_at': createdAt,
      };
}
