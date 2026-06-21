class Note {
  final int? id;
  final String title;
  final String content;
  final String category; // kept for backward compat, no longer used in UI
  final String groupName;
  final String createdAt;

  Note({
    this.id,
    required this.title,
    required this.content,
    this.category = '',
    this.groupName = '',
    required this.createdAt,
  });

  factory Note.fromMap(Map<String, dynamic> map) => Note(
    id: map['id'],
    title: map['title'],
    content: map['content'],
    category: map['category'] ?? '',
    groupName: map['group_name'] ?? '',
    createdAt: map['created_at'] ?? '',
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'content': content,
    'category': category,
    'group_name': groupName,
    'created_at': createdAt,
  };

  Note copyWith({int? id, String? title, String? content, String? category, String? groupName, String? createdAt}) =>
    Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      groupName: groupName ?? this.groupName,
      createdAt: createdAt ?? this.createdAt,
    );
}
