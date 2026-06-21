import '../database/database.dart';
import '../models/monitor_number.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

class MonitorNumberRepository {
  final _db = AppDatabase.instance;
 
  Future<void> save(MonitorNumber number) async {
    final db = await _db.database;
    await db.insert('monitor_numbers', number.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace);
  }
 
  Future<List<MonitorNumber>> getAll() async {
    final db = await _db.database;
    final result = await db.query('monitor_numbers', orderBy: 'id DESC');
    return result.map(MonitorNumber.fromMap).toList();
  }
 
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('monitor_numbers', where: 'id = ?', whereArgs: [id]);
  }
}