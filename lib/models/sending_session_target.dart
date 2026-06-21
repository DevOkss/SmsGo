class SendingSessionTarget {
  final int? id;
  final int sessionId;
  final int? leadId;
  final String phoneNumber;
  final int seqIndex;
  final String createdAt;

  SendingSessionTarget({
    this.id,
    required this.sessionId,
    this.leadId,
    required this.phoneNumber,
    required this.seqIndex,
    required this.createdAt,
  });

  factory SendingSessionTarget.fromMap(Map<String, dynamic> map) {
    return SendingSessionTarget(
      id: map['id'],
      sessionId: map['session_id'],
      leadId: map['lead_id'],
      phoneNumber: map['phone_number'].toString(),
      seqIndex: map['seq_index'] ?? 0,
      createdAt: map['created_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'lead_id': leadId,
        'phone_number': phoneNumber,
        'seq_index': seqIndex,
        'created_at': createdAt,
      };

  SendingSessionTarget copyWith({
    int? id,
    int? sessionId,
    int? leadId,
    String? phoneNumber,
    int? seqIndex,
    String? createdAt,
  }) {
    return SendingSessionTarget(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      leadId: leadId ?? this.leadId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      seqIndex: seqIndex ?? this.seqIndex,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

