class Reply {
  final int? id;
  final int? leadId;
  final String phoneNumber;
  final String message;
  final String receivedAt;
 
  Reply({
    this.id,
    this.leadId,
    required this.phoneNumber,
    required this.message,
    required this.receivedAt,
  });
 
  factory Reply.fromMap(Map<String, dynamic> map) => Reply(
    id: map['id'],
    leadId: map['lead_id'],
    phoneNumber: map['phone_number'].toString(),
    message: map['message']?.toString() ?? '',
    receivedAt: map['received_at']?.toString() ?? '',
  );
 
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'lead_id': leadId,
    'phone_number': phoneNumber,
    'message': message,
    'received_at': receivedAt,
  };
}