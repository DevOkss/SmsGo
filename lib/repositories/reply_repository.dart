import '../database/database.dart';
import '../models/sending_session.dart';

class SendingSessionRepository {
  final _db = AppDatabase.instance;
 
  Future<int> create(SendingSession session) async {
    final db = await _db.database;
    return db.insert('sending_sessions', session.toMap());
  }
 
  Future<List<SendingSession>> getActive() async {
    final db = await _db.database;
    final result = await db.query('sending_sessions',
      where: 'running = 1', orderBy: 'id DESC');
    return result.map(SendingSession.fromMap).toList();
  }
 
  Future<List<SendingSession>> getByCampaign(int campaignId) async {
    final db = await _db.database;
    final result = await db.query('sending_sessions',
      where: 'campaign_id = ?', whereArgs: [campaignId], orderBy: 'id DESC');
    return result.map(SendingSession.fromMap).toList();
  }
 
  Future<void> update(SendingSession session) async {
    final db = await _db.database;
    await db.update('sending_sessions', session.toMap(),
      where: 'id = ?', whereArgs: [session.id]);
  }
 
  Future<void> stop(int id) async {
    final db = await _db.database;
    await db.update('sending_sessions', {
      'running': 0,
      'ended_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }
}