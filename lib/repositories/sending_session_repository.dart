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
    // Show running sessions AND completed/stopped sessions (ended_at is set).
    // Completed = all targets processed; Stopped = user-initiated stop.
    final result = await db.query('sending_sessions',
      where: 'running = 1 OR ended_at IS NOT NULL',
      orderBy: 'id DESC');
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
 
  Future<void> pause(int id, {required String nextSendAtIso}) async {
    final db = await _db.database;
    await db.update('sending_sessions', {
      'paused': 1,
      'running': 1,
      'next_send_at': nextSendAtIso,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> resume(int id, {required String nextSendAtIso}) async {
    final db = await _db.database;
    await db.update('sending_sessions', {
      'paused': 0,
      'running': 1,
      'next_send_at': nextSendAtIso,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> stop(int id) async {
    final db = await _db.database;
    await db.update('sending_sessions', {
      'running': 0,
      'paused': 0,
      'next_send_at': null,
      'ended_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('sending_sessions', where: 'id = ?', whereArgs: [id]);
  }

}