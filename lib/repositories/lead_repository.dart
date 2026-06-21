import '../database/database.dart';
import '../models/lead.dart';

class LeadRepository {
  final _db = AppDatabase.instance;

  Future<void> insert(Lead lead) async {
    final db = await _db.database;
    await db.insert('leads', lead.toMap());
  }

  Future<void> insertMany(List<Lead> leads) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final lead in leads) {
      batch.insert('leads', lead.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<Lead>> getByCampaign(int campaignId, {String? network}) async {
    final db = await _db.database;
    String? where = 'campaign_id = ?';
    List<dynamic> whereArgs = [campaignId];

    if (network != null && network != 'All') {
      where = 'campaign_id = ? AND network = ?';
      whereArgs = [campaignId, network];
    }

    final result = await db.query('leads', where: where, whereArgs: whereArgs);
    return result.map(Lead.fromMap).toList();
  }

  Future<List<Lead>> getUnsent(int campaignId, {String? network, int? rangeStart, int? rangeEnd}) async {
    final db = await _db.database;
    String where = 'campaign_id = ? AND sent = 0 AND failed = 0';
    List<dynamic> whereArgs = [campaignId];

    if (network != null && network != 'All') {
      where += ' AND network = ?';
      whereArgs.add(network);
    }

    // Get all matching leads ordered by id, then apply range
    final result = await db.query('leads', where: where, whereArgs: whereArgs, orderBy: 'id ASC');

    if (rangeStart != null && rangeEnd != null) {
      // rangeStart/rangeEnd are 1-based user-facing indices
      final start = (rangeStart - 1).clamp(0, result.length);
      final end = rangeEnd.clamp(0, result.length);
      if (start < end) {
        return result.sublist(start, end).map(Lead.fromMap).toList();
      }
    }

    return result.map(Lead.fromMap).toList();
  }

  Future<int> getUnsentCount(int campaignId, {String? network}) async {
    final db = await _db.database;
    String where = 'campaign_id = ? AND sent = 0 AND failed = 0';
    List<dynamic> whereArgs = [campaignId];
    if (network != null && network != 'All') {
      where += ' AND network = ?';
      whereArgs.add(network);
    }
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM leads WHERE $where', whereArgs);
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<List<Lead>> getReplied(int? campaignId) async {
    final db = await _db.database;
    final result = await db.query(
      'leads',
      where: campaignId != null ? 'replied = 1 AND campaign_id = ?' : 'replied = 1',
      whereArgs: campaignId != null ? [campaignId] : null,
    );
    return result.map(Lead.fromMap).toList();
  }

  Future<void> markSent(int id) async {
    final db = await _db.database;
    await db.update('leads', {
      'sent': 1,
      'failed': 0,
      'sent_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markFailed(int id) async {
    final db = await _db.database;
    await db.update('leads', {'failed': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markReplied(String phoneNumber, String message) async {
    final db = await _db.database;
    await db.update('leads', {
      'replied': 1,
      'reply_message': message,
    }, where: 'phone_number = ?', whereArgs: [phoneNumber]);
  }

  Future<Map<String, int>> getNetworkCounts(int campaignId) async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT network, COUNT(*) as count
      FROM leads WHERE campaign_id = ?
      GROUP BY network
    ''', [campaignId]);

    final counts = <String, int>{};
    for (final row in result) {
      counts[row['network'] as String] = row['count'] as int;
    }
    return counts;
  }

  Future<Map<String, int>> getUnsentNetworkCounts(int campaignId) async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT network, COUNT(*) as count
      FROM leads
      WHERE campaign_id = ? AND sent = 0 AND failed = 0
      GROUP BY network
    ''', [campaignId]);

    final counts = <String, int>{};
    for (final row in result) {
      counts[row['network'] as String] = row['count'] as int;
    }
    return counts;
  }

  Future<int> deleteAllByCampaign(int campaignId) async {
    final db = await _db.database;
    return await db.delete('leads', where: 'campaign_id = ?', whereArgs: [campaignId]);
  }

  /// Check which phone numbers from the list already exist in the target campaign.
  Future<Set<String>> findDuplicatesInCampaign(int campaignId, List<String> phoneNumbers) async {
    if (phoneNumbers.isEmpty) return {};
    final db = await _db.database;
    final placeholders = List.filled(phoneNumbers.length, '?').join(',');
    final result = await db.rawQuery(
      'SELECT DISTINCT phone_number FROM leads WHERE campaign_id = ? AND phone_number IN ($placeholders)',
      [campaignId, ...phoneNumbers],
    );
    return result.map((r) => r['phone_number'] as String).toSet();
  }

  /// Find which phone numbers exist in other campaigns (not the target).
  Future<List<Map<String, dynamic>>> findCrossCampaignDuplicates(
    int targetCampaignId,
    List<String> phoneNumbers,
  ) async {
    if (phoneNumbers.isEmpty) return [];
    final db = await _db.database;
    final placeholders = List.filled(phoneNumbers.length, '?').join(',');
    return await db.rawQuery('''
      SELECT l.phone_number, l.campaign_id, c.name as campaign_name, l.name
      FROM leads l
      JOIN campaigns c ON c.id = l.campaign_id
      WHERE l.campaign_id != ? AND l.phone_number IN ($placeholders)
      GROUP BY l.phone_number, l.campaign_id
      ORDER BY l.phone_number ASC
    ''', [targetCampaignId, ...phoneNumbers]);
  }

}
