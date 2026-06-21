class SendingSessionState {
  final int? id;
  final int sessionId;
  final int cursorIndex;
  final String createdAt;
  final String updatedAt;

  SendingSessionState({
    this.id,
    required this.sessionId,
    required this.cursorIndex,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SendingSessionState.fromMap(Map<String, dynamic> map) {
    return SendingSessionState(
      id: map['id'],
      sessionId: map['session_id'],
      cursorIndex: map['cursor_index'] ?? 0,
      createdAt: map['created_at']?.toString() ?? '',
      updatedAt: map['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'cursor_index': cursorIndex,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  SendingSessionState copyWith({
    int? id,
    int? sessionId,
    int? cursorIndex,
    String? createdAt,
    String? updatedAt,
  }) {
    return SendingSessionState(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      cursorIndex: cursorIndex ?? this.cursorIndex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

