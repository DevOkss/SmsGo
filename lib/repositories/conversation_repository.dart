import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../models/conversation.dart';
import '../models/conversation_message.dart';

/// Normalizes a Philippine phone number to a consistent format for comparison.
/// +639XXXXXXXXX, 09XXXXXXXXX, 639XXXXXXXXX all become 09XXXXXXXXX.
/// Returns the original string if it doesn't look like a phone number (e.g. named senders like "SSS NDRRMC").
String normalizePhone(String phone) {
  var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  // If it has fewer than 7 digits, it's not a phone number — preserve original
  if (digits.length < 7) return phone.trim();
  if (digits.startsWith('63') && digits.length >= 11) {
    digits = '0' + digits.substring(2);
  }
  if (digits.length >= 10 && digits.startsWith('9')) {
    digits = '0' + digits;
  }
  return digits;
}

/// Returns true if the phone number looks like a real phone number (not a shortcode or named sender).
bool isRealPhoneNumber(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 10;
}

class ConversationRepository {
  final Database db;

  /// Broadcast stream that emits when read/unread status or ownership changes.
  /// Listeners should refresh badge counts.
  static final _changeController = StreamController<void>.broadcast();
  static Stream<void> get onChange => _changeController.stream;

  ConversationRepository(this.db);

  Future<int> createConversation(int? sessionId, String phoneNumber, {int? leadId, int? campaignId}) async {
    final now = DateTime.now().toIso8601String();
    final normalizedPhone = normalizePhone(phoneNumber);

    // Dedup: if campaignId is set, find existing conversation for this campaign+phone
    if (campaignId != null) {
      final existing = await db.rawQuery(
        'SELECT id FROM conversations WHERE campaign_id = ? AND phone_number = ? LIMIT 1',
        [campaignId, normalizedPhone],
      );
      if (existing.isNotEmpty) {
        final existingId = existing.first['id'] as int;
        // Re-associate session_id so conversation moves back to Active Sending
        if (sessionId != null) {
          await db.update('conversations', {'session_id': sessionId}, where: 'id = ?', whereArgs: [existingId]);
        }
        return existingId;
      }

      // Also check for standalone conversations (campaign_id IS NULL) for the same phone number
      // and consolidate them into this campaign to prevent duplicates
      final standalone = await db.rawQuery(
        'SELECT id FROM conversations WHERE campaign_id IS NULL AND phone_number = ? LIMIT 1',
        [normalizedPhone],
      );
      if (standalone.isNotEmpty) {
        final standaloneId = standalone.first['id'] as int;
        await db.update('conversations', {
          'campaign_id': campaignId,
          'session_id': sessionId,
          if (leadId != null) 'lead_id': leadId,
        }, where: 'id = ?', whereArgs: [standaloneId]);
        return standaloneId;
      }
    }

    // Dedup: if both sessionId and campaignId are null (test send / imported), find existing conversation for this phone
    if (sessionId == null && campaignId == null) {
      final existing = await db.rawQuery(
        "SELECT id FROM conversations WHERE session_id IS NULL AND campaign_id IS NULL AND phone_number = ? LIMIT 1",
        [normalizedPhone],
      );
      if (existing.isNotEmpty) {
        return existing.first['id'] as int;
      }
    }

    final id = await db.insert('conversations', {
      'session_id': sessionId,
      'campaign_id': campaignId,
      'lead_id': leadId,
      'phone_number': normalizedPhone,
      'last_message': null,
      'replied': 0,
      'created_at': now,
    });
    return id;
  }

  Future<int> addMessage(
    int conversationId,
    String direction,
    String message, {
    String? status,
    String? createdAt,
    String? simSlot,
    int? sessionId,
  }) async {
    final now = createdAt ?? DateTime.now().toIso8601String();
    final effectiveStatus = status ?? (direction == 'out' ? 'sent' : '');
    final id = await db.insert('conversation_messages', {
      'conversation_id': conversationId,
      'session_id': sessionId,
      'direction': direction,
      'message': message,
      'status': effectiveStatus,
      'sim_slot': simSlot,
      'created_at': now,
    });

    // update last_message on conversation
    await db.update(
      'conversations',
      {'last_message': message},
      where: 'id = ?',
      whereArgs: [conversationId],
    );

    return id;
  }

  Future<List<Conversation>> getConversationsForSession(int sessionId, {bool? replied, bool contactedOnly = true}) async {
    final where = <String>[];
    final whereArgs = <dynamic>[];

    where.add('c.session_id = ?');
    whereArgs.add(sessionId);

    // Only show conversations that have at least one message
    if (contactedOnly) {
      where.add('EXISTS (SELECT 1 FROM conversation_messages cm WHERE cm.conversation_id = c.id)');
    }

    if (replied == true) {
      // Replied = has at least one incoming message
      where.add('EXISTS (SELECT 1 FROM conversation_messages cm WHERE cm.conversation_id = c.id AND cm.direction = \'in\')');
    }

    final rows = await db.rawQuery('''
      SELECT c.*,
             COALESCE(
               (SELECT MAX(cm.created_at) FROM conversation_messages cm WHERE cm.conversation_id = c.id),
               c.created_at
             ) as last_activity,
             (SELECT cm2.status FROM conversation_messages cm2
              WHERE cm2.conversation_id = c.id AND cm2.direction = 'out'
              ORDER BY cm2.created_at DESC LIMIT 1) as outgoing_status,
             (SELECT cm3.direction FROM conversation_messages cm3
              WHERE cm3.conversation_id = c.id
              ORDER BY cm3.created_at DESC LIMIT 1) as last_direction
      FROM conversations c
      WHERE ${where.join(' AND ')}
      ORDER BY last_activity DESC
    ''', whereArgs);

    return rows.map((r) => Conversation.fromMap(r)).toList();
  }

  Future<List<Conversation>> getConversationsForCampaign(int campaignId, {bool? replied, bool contactedOnly = true}) async {
    final where = <String>[];
    final whereArgs = <dynamic>[];

    where.add('c.campaign_id = ?');
    whereArgs.add(campaignId);

    // Only show conversations with an active session (not orphaned to Imported Messages)
    where.add('c.session_id IS NOT NULL');

    if (contactedOnly) {
      where.add('EXISTS (SELECT 1 FROM conversation_messages cm WHERE cm.conversation_id = c.id)');
    }

    if (replied == true) {
      where.add('EXISTS (SELECT 1 FROM conversation_messages cm WHERE cm.conversation_id = c.id AND cm.direction = \'in\')');
    }

    final rows = await db.rawQuery('''
      SELECT c.*,
             COALESCE(
               (SELECT MAX(cm.created_at) FROM conversation_messages cm WHERE cm.conversation_id = c.id),
               c.created_at
             ) as last_activity,
             (SELECT cm2.status FROM conversation_messages cm2
              WHERE cm2.conversation_id = c.id AND cm2.direction = 'out'
              ORDER BY cm2.created_at DESC LIMIT 1) as outgoing_status,
             (SELECT cm3.direction FROM conversation_messages cm3
              WHERE cm3.conversation_id = c.id
              ORDER BY cm3.created_at DESC LIMIT 1) as last_direction
      FROM conversations c
      WHERE ${where.join(' AND ')}
      ORDER BY last_activity DESC
    ''', whereArgs);

    return rows.map((r) => Conversation.fromMap(r)).toList();
  }

  Future<List<ConversationMessage>> getMessagesForConversation(int conversationId) async {
    final rows = await db.query(
      'conversation_messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );

    return rows.map((r) => ConversationMessage.fromMap(r)).toList();
  }

  /// Returns the status of the latest outgoing message for a conversation.
  /// If there is no outgoing message yet, returns null.
  Future<String?> getLatestOutgoingStatusForConversation(int conversationId) async {
    final rows = await db.query(
      'conversation_messages',
      where: 'conversation_id = ? AND direction = ?',
      whereArgs: [conversationId, 'out'],
      orderBy: 'created_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first['status'] as String?;
  }

  /// Batch helper for building conversation list UI.
  /// Uses a single grouped query instead of N individual queries.
  Future<Map<int, String?>> getLatestOutgoingStatusesForConversations(List<int> conversationIds) async {
    if (conversationIds.isEmpty) return {};
    final result = <int, String?>{};
    // Initialize all IDs with null (in case they have no outgoing messages)
    for (final id in conversationIds) {
      result[id] = null;
    }
    // Single query using IN clause and GROUP BY
    final placeholders = conversationIds.map((_) => '?').join(',');
    final rows = await db.rawQuery('''
      SELECT cm.conversation_id, cm.status
      FROM conversation_messages cm
      INNER JOIN (
        SELECT conversation_id, MAX(created_at) as max_created
        FROM conversation_messages
        WHERE conversation_id IN ($placeholders) AND direction = 'out'
        GROUP BY conversation_id
      ) latest ON cm.conversation_id = latest.conversation_id
        AND cm.created_at = latest.max_created
        AND cm.direction = 'out'
    ''', conversationIds);
    for (final row in rows) {
      final convId = row['conversation_id'] as int;
      result[convId] = row['status'] as String?;
    }
    return result;
  }


  Future<void> markReplied(int conversationId, bool replied) async {
    await db.update(
      'conversations',
      {'replied': replied ? 1 : 0},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> markRead(int conversationId) async {
    await db.update(
      'conversations',
      {'unread': 0},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    _changeController.add(null);
  }

  Future<void> markUnread(int conversationId) async {
    await db.update(
      'conversations',
      {'unread': 1},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    _changeController.add(null);
  }

  /// Marks all conversations for a campaign as read.
  Future<void> markAllReadForCampaign(int campaignId) async {
    await db.update(
      'conversations',
      {'unread': 0},
      where: 'campaign_id = ?',
      whereArgs: [campaignId],
    );
    _changeController.add(null);
  }

  /// Marks all conversations for a session as read.
  Future<void> markAllReadForSession(int sessionId) async {
    await db.update(
      'conversations',
      {'unread': 0},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    _changeController.add(null);
  }

  Future<void> deleteConversation(int conversationId) async {
    await db.delete(
      'conversation_messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
    await db.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  /// Clear session_id on all conversations linked to a session.
  /// Keeps campaign_id for re-association when a new session starts.
  /// This makes conversations accessible in Imported Messages when no active session exists.
  Future<void> clearSessionLink(int sessionId) async {
    await db.update(
      'conversations',
      {'session_id': null},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    _changeController.add(null);
  }

  Future<void> deleteAllConversations() async {
    await db.delete('conversation_messages');
    await db.delete('conversations');
  }

  Future<void> updateMessageStatus(int messageId, String status) async {
    await db.update(
      'conversation_messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Returns all conversations across all sessions, joined with session SIM info.
  /// Sorted by latest message time (most recent first).
  /// By default, only returns conversations without a session (imported/direct).
  Future<List<Map<String, dynamic>>> getAllConversations({bool? replied, bool? unread, bool includeSessionConversations = false}) async {
    final where = <String>[];
    final whereArgs = <dynamic>[];

    // By default, only show conversations without an active session (imported/direct/orphaned campaign conversations)
    // Also exclude conversations whose campaign still has an active session (running = 1)
    if (!includeSessionConversations) {
      where.add('c.session_id IS NULL');
      where.add('c.campaign_id NOT IN (SELECT ss.campaign_id FROM sending_sessions ss WHERE ss.running = 1)');
    }

    if (replied != null) {
      if (replied) {
        where.add("(SELECT cm4.direction FROM conversation_messages cm4 WHERE cm4.conversation_id = c.id ORDER BY cm4.created_at DESC LIMIT 1) = 'out'");
      } else {
        where.add("((SELECT cm4.direction FROM conversation_messages cm4 WHERE cm4.conversation_id = c.id ORDER BY cm4.created_at DESC LIMIT 1) IS NULL OR (SELECT cm4.direction FROM conversation_messages cm4 WHERE cm4.conversation_id = c.id ORDER BY cm4.created_at DESC LIMIT 1) != 'out')");
      }
    }

    if (unread != null) {
      where.add('c.unread = ?');
      whereArgs.add(unread ? 1 : 0);
    }

    final whereClause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT c.*, ss.sim_slot, ss.campaign_id,
             COALESCE(
               (SELECT MAX(cm.created_at) FROM conversation_messages cm WHERE cm.conversation_id = c.id),
               c.created_at
             ) as last_activity,
             (SELECT cm2.status FROM conversation_messages cm2
              WHERE cm2.conversation_id = c.id AND cm2.direction = 'out'
              ORDER BY cm2.created_at DESC LIMIT 1) as outgoing_status,
             (SELECT cm3.direction FROM conversation_messages cm3
              WHERE cm3.conversation_id = c.id
              ORDER BY cm3.created_at DESC LIMIT 1) as last_direction
      FROM conversations c
      LEFT JOIN sending_sessions ss ON c.session_id = ss.id
      $whereClause
      ORDER BY last_activity DESC
    ''', whereArgs);

    return rows;
  }

  /// Returns count of unread conversations.
  Future<int> getUnreadCount() async {
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM conversations WHERE unread = 1');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns count of unread conversations for a specific session.
  Future<int> getUnreadCountForSession(int sessionId) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM conversations WHERE unread = 1 AND session_id = ?',
      [sessionId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns count of unread conversations in Imported Messages (session_id IS NULL and no active session for campaign).
  Future<int> getUnreadCountForImported() async {
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM conversations WHERE unread = 1 AND session_id IS NULL AND campaign_id NOT IN (SELECT ss.campaign_id FROM sending_sessions ss WHERE ss.running = 1)",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> togglePauseSession(int sessionId, bool pause) async {
    final Map<String, Object?> values = {'paused': pause ? 1 : 0};
    if (!pause) {
      values['next_send_at'] = DateTime.now().toIso8601String();
    }
    await db.update(
      'sending_sessions',
      values,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }
}


