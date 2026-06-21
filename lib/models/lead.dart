class Lead {
  final int? id;
  final int campaignId;
  final String? name;
  final String phoneNumber;
  final String network;
  final bool sent;
  final bool failed;
  final bool replied;
  final String? replyMessage;
  final String? sentAt;
 
  Lead({
    this.id,
    required this.campaignId,
    this.name,
    required this.phoneNumber,
    required this.network,
    this.sent = false,
    this.failed = false,
    this.replied = false,
    this.replyMessage,
    this.sentAt,
  });
 
  factory Lead.fromMap(Map<String, dynamic> map) => Lead(
    id: map['id'],
    campaignId: map['campaign_id'],
    name: map['name']?.toString(),
    phoneNumber: map['phone_number'].toString(),
    network: (map['network'] ?? 'Others').toString(),
    sent: map['sent'] == 1,
    failed: map['failed'] == 1,
    replied: map['replied'] == 1,
    replyMessage: map['reply_message'],
    sentAt: map['sent_at'],
  );
 
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'campaign_id': campaignId,
    'name': name,
    'phone_number': phoneNumber,
    'network': network,
    'sent': sent ? 1 : 0,
    'failed': failed ? 1 : 0,
    'replied': replied ? 1 : 0,
    'reply_message': replyMessage,
    'sent_at': sentAt,
  };
 
  Lead copyWith({
    int? id, int? campaignId, String? name, String? phoneNumber,
    String? network, bool? sent, bool? failed, bool? replied,
    String? replyMessage, String? sentAt,
  }) => Lead(
    id: id ?? this.id,
    campaignId: campaignId ?? this.campaignId,
    name: name ?? this.name,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    network: network ?? this.network,
    sent: sent ?? this.sent,
    failed: failed ?? this.failed,
    replied: replied ?? this.replied,
    replyMessage: replyMessage ?? this.replyMessage,
    sentAt: sentAt ?? this.sentAt,
  );
}