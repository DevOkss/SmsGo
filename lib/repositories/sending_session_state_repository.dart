import '../database/database.dart';
import '../models/sending_session_state.dart';

class SendingSessionStateRepository {
  final _db = AppDatabase.instance;

  Future<void> upsert(SendingSessionState state) async {
    final db = await _db.database;

    // SQLite upsert behavior for older versions: do update then insert fallback.
    final existing = await db.query(
      'sending_session_state',
      where: 'session_id = ?',
      whereArgs: [state.sessionId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await db.update(
        'sending_session_state',
        state.toMap()..remove('id'),
        where: 'session_id = ?',
        whereArgs: [state.sessionId],
      );
      return;
    }

    await db.insert('sending_session_state', {
      'session_id': state.sessionId,
      'cursor_index': state.cursorIndex,
      'created_at': state.createdAt,
      'updated_at': state.updatedAt,
    });
  }

  Future<void> deleteBySession(int sessionId) async {
    final db = await _db.database;
    await db.delete('sending_session_state', where: 'session_id = ?', whereArgs: [sessionId]);
  }

  Future<SendingSessionState?> getBySession(int sessionId) async {
    final db = await _db.database;
    final result = await db.query(
      'sending_session_state',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return SendingSessionState.fromMap(result.first);
  }
}

