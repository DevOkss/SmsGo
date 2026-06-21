import '../database/database.dart';

class SendLogRepository {
  final _db = AppDatabase.instance;

  Future<List<Map<String, dynamic>>> getBySession(int sessionId) async {
    final db = await _db.database;
    return db.rawQuery('''
      SELECT sl.id as id,
             sl.session_id,
             sl.lead_id,
             sl.phone_number,
             sl.message,
             sl.status,
             sl.created_at
      FROM send_logs sl
      WHERE sl.session_id = ?
      ORDER BY sl.created_at DESC
    ''', [sessionId]);
  }

  Future<List<String>> getTargetPhoneNumbersForSession(int sessionId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT l.phone_number as phone_number
      FROM send_logs sl
      JOIN leads l ON l.id = sl.lead_id
      WHERE sl.session_id = ?
    ''', [sessionId]);

    return rows.map((r) => r['phone_number'].toString()).toList();
  }
}

