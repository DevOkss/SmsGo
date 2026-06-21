import '../database/database.dart';
import '../models/note.dart';

class NoteRepository {
  final _db = AppDatabase.instance;

  Future<int> create(Note note) async {
    final db = await _db.database;
    return db.insert('notes', note.toMap());
  }

  Future<List<Note>> getAll() async {
    final db = await _db.database;
    final result = await db.query('notes', orderBy: 'id ASC');
    return result.map(Note.fromMap).toList();
  }

  Future<List<Note>> getByGroup(String groupName) async {
    final db = await _db.database;
    final result = await db.query('notes',
      where: 'group_name = ?', whereArgs: [groupName], orderBy: 'id ASC');
    return result.map(Note.fromMap).toList();
  }

  // Group operations using note_groups table

  Future<int> createGroup(String name) async {
    final db = await _db.database;
    return db.insert('note_groups', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getAllGroupsWithCounts() async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT ng.name as group_name,
             COALESCE(COUNT(n.id), 0) as note_count
      FROM note_groups ng
      LEFT JOIN notes n ON n.group_name = ng.name
      GROUP BY ng.name
      ORDER BY ng.name ASC
    ''');
    return result;
  }

  Future<void> renameGroup(String oldName, String newName) async {
    final db = await _db.database;
    await db.update(
      'note_groups',
      {'name': newName},
      where: 'name = ?',
      whereArgs: [oldName],
    );
    await db.update(
      'notes',
      {'group_name': newName},
      where: 'group_name = ?',
      whereArgs: [oldName],
    );
  }

  Future<void> deleteGroup(String groupName) async {
    final db = await _db.database;
    await db.delete('notes', where: 'group_name = ?', whereArgs: [groupName]);
    await db.delete('note_groups', where: 'name = ?', whereArgs: [groupName]);
  }

  Future<int> update(Note note) async {
    final db = await _db.database;
    return db.update('notes', note.toMap(), where: 'id = ?', whereArgs: [note.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}
