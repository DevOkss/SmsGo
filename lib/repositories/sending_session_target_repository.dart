import '../database/database.dart';
import '../models/sending_session_target.dart';

class SendingSessionTargetRepository {
  final _db = AppDatabase.instance;

  Future<void> insertMany(List<SendingSessionTarget> targets) async {
    if (targets.isEmpty) return;
    final db = await _db.database;
    final batch = db.batch();
    for (final t in targets) {
      batch.insert('sending_session_targets', t.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteBySession(int sessionId) async {
    final db = await _db.database;
    await db.delete('sending_session_targets', where: 'session_id = ?', whereArgs: [sessionId]);
  }

  Future<List<SendingSessionTarget>> getBySession(int sessionId) async {
    final db = await _db.database;
    final result = await db.query(
      'sending_session_targets',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'seq_index ASC',
    );
    return result.map((m) => SendingSessionTarget.fromMap(m)).toList();
  }

  Future<List<SendingSessionTarget>> getBySessionFiltered(int sessionId, {required int fromCursorIndex}) async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT * FROM sending_session_targets
      WHERE session_id = ? AND seq_index >= ?
      ORDER BY seq_index ASC
    ''', [sessionId, fromCursorIndex]);
    return result.map((m) => SendingSessionTarget.fromMap(m)).toList();
  }
}

