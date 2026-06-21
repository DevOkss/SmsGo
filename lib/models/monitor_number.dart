class MonitorNumber {
  final int? id;
  final String phoneNumber;
  final String? label;
  final String createdAt;
 
  MonitorNumber({
    this.id,
    required this.phoneNumber,
    this.label,
    required this.createdAt,
  });
 
  factory MonitorNumber.fromMap(Map<String, dynamic> map) => MonitorNumber(
    id: map['id'],
    phoneNumber: map['phone_number'].toString(),
    label: map['label']?.toString(),
    createdAt: map['created_at']?.toString() ?? '',
  );
 
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'phone_number': phoneNumber,
    'label': label,
    'created_at': createdAt,
  };
}