import 'package:flutter/foundation.dart';
import '../models/note.dart';
import '../repositories/notes_repository.dart';

class NotesProvider extends ChangeNotifier {
  final _repo = NoteRepository();

  List<Note> _notes = [];
  List<Note> get notes => _notes;

  // Backward compat: messaging screen uses these
  List<Note> get rotational => _notes;
  List<Note> get sequential => _notes;

  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> get groups => _groups;

  bool _loading = false;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _notes = await _repo.getAll();
    _groups = await _repo.getAllGroupsWithCounts();
    _loading = false;
    notifyListeners();
  }

  Future<void> loadGroup(String groupName) async {
    _loading = true;
    notifyListeners();
    _notes = await _repo.getByGroup(groupName);
    _loading = false;
    notifyListeners();
  }

  Future<List<Note>> getNotesByGroup(String groupName) async {
    return await _repo.getByGroup(groupName);
  }

  Future<void> createGroup(String name) async {
    await _repo.createGroup(name);
    await load();
  }

  Future<void> renameGroup(String oldName, String newName) async {
    await _repo.renameGroup(oldName, newName);
    await load();
  }

  Future<void> deleteGroup(String groupName) async {
    await _repo.deleteGroup(groupName);
    await load();
  }

  Future<void> create(String title, String content, String groupName) async {
    await _repo.create(Note(
      title: title,
      content: content,
      groupName: groupName,
      createdAt: DateTime.now().toIso8601String(),
    ));
  }

  Future<void> update(Note note) async {
    await _repo.update(note);
  }

  Future<void> delete(int id) async {
    await _repo.delete(id);
  }
}
