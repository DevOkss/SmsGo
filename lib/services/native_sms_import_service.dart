import 'package:flutter/foundation.dart';

import '../database/database.dart';
import '../repositories/conversation_repository.dart';
import '../services/sms_import_gateway.dart';


/// Imports native SMS rows into the app DB.
///
/// TODO.md mapping:
/// - method-channel import
/// - create/find `conversations`
/// - insert `conversation_messages`
class NativeSmsImportService {
  final _db = AppDatabase.instance;

  Future<void> importSmsHistoryToSession({
    required int sessionId,
    required List<String> types,
    DateTime? since,
    required bool moveToActive,
  }) async {
    final db = await _db.database;
    final convRepo = ConversationRepository(db);

    final rows = await SmsImportGateway.importSmsHistory(
      types: types,
      sinceEpochMillis: since?.millisecondsSinceEpoch,
    );

    // Resolve active campaign lead phone numbers if moving to active.
    // session -> campaign -> leads
    final Map<String, int> activeLeadByPhone = {};

    if (moveToActive) {
      final sess = await db.query(
        'sending_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );

      if (sess.isNotEmpty) {
        final campaignId = sess.first['campaign_id'] as int?;
        if (campaignId != null) {
          final leadRows = await db.query(
            'leads',
            where: 'campaign_id = ?',
            whereArgs: [campaignId],
          );
          for (final l in leadRows) {
            final phone = (l['phone_number'] as String?)?.trim();
            final leadId = l['id'] as int?;
            if (phone != null && phone.isNotEmpty && leadId != null) {
              activeLeadByPhone[phone] = leadId;
            }
          }
        }
      }
    }

    // Track which conversations have unread incoming messages
    final Map<int, bool> convHasUnread = {};

    // Batch fetch existing conversations for all phone numbers (single query)
    final normalizedAddresses = <String>[];
    final originalByNormalized = <String, String>{};
    for (final row in rows) {
      final address = (row['address'] as String? ?? '').trim();
      if (address.isEmpty) continue;
      final normalized = normalizePhone(address);
      normalizedAddresses.add(normalized);
      originalByNormalized[normalized] = address;
    }

    final Map<String, int> existingConversations = {};
    if (normalizedAddresses.isNotEmpty) {
      final uniquePhones = normalizedAddresses.toSet().toList();
      final placeholders = uniquePhones.map((_) => '?').join(',');
      final convRows = await db.query(
        'conversations',
        columns: ['id', 'phone_number'],
        where: 'phone_number IN ($placeholders)',
        whereArgs: uniquePhones,
      );
      for (final cr in convRows) {
        final phone = cr['phone_number'] as String;
        final id = cr['id'] as int;
        if (!existingConversations.containsKey(phone)) {
          existingConversations[phone] = id;
        }
      }
    }

    // Process all rows in a transaction for better performance
    await db.transaction((txn) async {
      for (final row in rows) {
        final address = (row['address'] as String? ?? '').trim();
        final body = (row['body'] as String? ?? '').trim();
        final type = (row['type'] as String? ?? 'inbox');
        final nativeDate = row['date'];
        final nativeRead = row['read'];

        if (address.isEmpty || body.isEmpty) continue;

        final direction = type == 'sent' ? 'out' : 'in';

        final epochMillis = nativeDate is int
            ? nativeDate
            : (nativeDate is double ? nativeDate.toInt() : null);
        if (epochMillis == null) continue;

        final createdAt = DateTime.fromMillisecondsSinceEpoch(epochMillis).toIso8601String();

        final normalizedAddress = normalizePhone(address);
        final leadId = moveToActive ? activeLeadByPhone[address] : null;

        var conversationId = existingConversations[normalizedAddress];
        if (conversationId == null) {
          conversationId = await convRepo.createConversation(sessionId, normalizedAddress, leadId: leadId);
          existingConversations[normalizedAddress] = conversationId;
        }

        // Check for duplicate message
        final dupRows = await txn.rawQuery(
          "SELECT id FROM conversation_messages WHERE conversation_id = ? AND direction = ? AND TRIM(message) = TRIM(?) LIMIT 1",
          [conversationId, direction, body],
        );

        if (dupRows.isNotEmpty) continue;

        await convRepo.addMessage(
          conversationId,
          direction,
          body,
          status: direction == 'out' ? 'sent' : '',
          createdAt: createdAt,
        );

        // Track unread: incoming messages where native read == 0 means unread
        if (direction == 'in') {
          final isRead = nativeRead is int ? nativeRead == 1 : true;
          if (!isRead) {
            convHasUnread[conversationId] = true;
          }
        }
      }
    });

    // Mark conversations with unread incoming messages
    for (final entry in convHasUnread.entries) {
      await convRepo.markUnread(entry.key);
    }

    debugPrint('Imported ${rows.length} native sms rows into session $sessionId');
  }
}


