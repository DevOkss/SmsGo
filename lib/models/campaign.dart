class Campaign {
  final int? id;
  final String name;
  final int totalLeads;
  final int sentCount;
  final int failedCount;
  final bool completed;
  final bool archived;
  final String createdAt;
 
  Campaign({
    this.id,
    required this.name,
    this.totalLeads = 0,
    this.sentCount = 0,
    this.failedCount = 0,
    this.completed = false,
    this.archived = false,
    required this.createdAt,
  });
 
  factory Campaign.fromMap(Map<String, dynamic> map) => Campaign(
    id: map['id'],
    name: map['name'],
    totalLeads: map['total_leads'] ?? 0,
    sentCount: map['sent_count'] ?? 0,
    failedCount: map['failed_count'] ?? 0,
    completed: map['completed'] == 1,
    archived: map['archived'] == 1,
    createdAt: map['created_at'],
  );
 
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'total_leads': totalLeads,
    'sent_count': sentCount,
    'failed_count': failedCount,
    'completed': completed ? 1 : 0,
    'archived': archived ? 1 : 0,
    'created_at': createdAt,
  };
 
  Campaign copyWith({
    int? id, String? name, int? totalLeads, int? sentCount,
    int? failedCount, bool? completed, bool? archived, String? createdAt,
  }) => Campaign(
    id: id ?? this.id,
    name: name ?? this.name,
    totalLeads: totalLeads ?? this.totalLeads,
    sentCount: sentCount ?? this.sentCount,
    failedCount: failedCount ?? this.failedCount,
    completed: completed ?? this.completed,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
  );
 
double get progress => totalLeads > 0 ? sentCount / totalLeads : 0.0;
}