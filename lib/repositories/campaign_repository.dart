import '../database/database.dart';
import '../models/campaign.dart';

class CampaignRepository {
  final _db = AppDatabase.instance;
 
  Future<int> insert(Campaign campaign) async {
    final db = await _db.database;
    return db.insert('campaigns', campaign.toMap());
  }
 
  Future<List<Campaign>> getAll({bool includeArchived = false}) async {
    final db = await _db.database;
    final result = await db.query(
      'campaigns',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'id DESC',
    );
    return result.map(Campaign.fromMap).toList();
  }
 
  Future<Campaign?> getById(int id) async {
    final db = await _db.database;
    final result = await db.query('campaigns', where: 'id = ?', whereArgs: [id], limit: 1);
    if (result.isEmpty) return null;
    return Campaign.fromMap(result.first);
  }
 
  Future<void> update(Campaign campaign) async {
    final db = await _db.database;
    await db.update('campaigns', campaign.toMap(), where: 'id = ?', whereArgs: [campaign.id]);
  }
 
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('campaigns', where: 'id = ?', whereArgs: [id]);
  }
 
  Future<void> archive(int id) async {
    final db = await _db.database;
    await db.update('campaigns', {'archived': 1, 'completed': 1}, where: 'id = ?', whereArgs: [id]);
  }
 
  Future<void> updateCounts(int id) async {
    final db = await _db.database;
    await db.rawUpdate('''
      UPDATE campaigns SET
        total_leads = (SELECT COUNT(*) FROM leads WHERE campaign_id = ?),
        sent_count = (
          SELECT COUNT(DISTINCT c.phone_number)
          FROM conversation_messages cm
          JOIN conversations c ON c.id = cm.conversation_id
          WHERE c.campaign_id = ? AND cm.direction = 'out' AND cm.status = 'sent'
        ),
        failed_count = (
          SELECT COUNT(DISTINCT c.phone_number)
          FROM conversation_messages cm
          JOIN conversations c ON c.id = cm.conversation_id
          WHERE c.campaign_id = ? AND cm.direction = 'out' AND cm.status = 'failed'
        )
      WHERE id = ?
    ''', [id, id, id, id]);
  }
}