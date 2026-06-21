import 'package:flutter/foundation.dart';

import '../database/database.dart';
import '../repositories/conversation_repository.dart';
import '../services/sms_import_gateway.dart';
import 'native_sms_import_service.dart';

/// Small wrapper that can be called by UI.
class NativeSmsImportController {
  final _service = NativeSmsImportService();

  Future<void> importForSession({
    required int sessionId,
    required bool moveToActive,
    required List<String> types,
  }) async {
    await _service.importSmsHistoryToSession(
      sessionId: sessionId,
      types: types,
      since: null,
      moveToActive: moveToActive,
    );

    debugPrint('Native SMS import completed for session=$sessionId');
  }

  /// Import all SMS without creating a campaign or session.
  /// Conversations are stored with session_id = null.
  /// [onProgress] is called with (current, total) during processing.
  Future<void> importAll({
    required List<String> types,
    void Function(int current, int total)? onProgress,
  }) async {
    final db = await AppDatabase.instance.database;
    final convRepo = ConversationRepository(db);

    debugPrint('[SmsGo] importAll: querying native SMS for types=$types');
    final rows = await SmsImportGateway.importSmsHistory(
      types: types,
      sinceEpochMillis: null,
    );
    debugPrint('[SmsGo] importAll: got ${rows.length} rows from native');

    final total = rows.length;
    final Map<int, bool> convHasUnread = {};
    int created = 0;
    int skipped = 0;

    for (int i = 0; i < total; i++) {
      final row = rows[i];
      final address = (row['address'] as String? ?? '').trim();
      final body = (row['body'] as String? ?? '').trim();
      final type = (row['type'] as String? ?? 'inbox');
      final nativeDate = row['date'];
      final nativeRead = row['read'];

      if (address.isEmpty || body.isEmpty) {
        onProgress?.call(i + 1, total);
        continue;
      }

      final direction = type == 'sent' ? 'out' : 'in';

      final epochMillis = nativeDate is int
          ? nativeDate
          : (nativeDate is double ? nativeDate.toInt() : null);
      if (epochMillis == null) {
        onProgress?.call(i + 1, total);
        continue;
      }

      final createdAt = DateTime.fromMillisecondsSinceEpoch(epochMillis).toIso8601String();

      // Find existing conversation for this phone number (normalized)
      final normalizedAddress = normalizePhone(address);
      final convRows = await db.rawQuery(
        "SELECT * FROM conversations WHERE phone_number = ? OR phone_number = ? ORDER BY created_at DESC LIMIT 1",
        [normalizedAddress, address],
      );

      final conversationId = convRows.isNotEmpty
          ? (convRows.first['id'] as int?)
          : await convRepo.createConversation(null, normalizedAddress);

      if (conversationId == null) {
        onProgress?.call(i + 1, total);
        continue;
      }

      // Dedup check — match by conversation + direction + message (trimmed)
      final dupRows = await db.rawQuery(
        "SELECT id FROM conversation_messages WHERE conversation_id = ? AND direction = ? AND TRIM(message) = TRIM(?) LIMIT 1",
        [conversationId, direction, body],
      );

      if (dupRows.isNotEmpty) {
        skipped++;
        onProgress?.call(i + 1, total);
        continue;
      }

      await convRepo.addMessage(
        conversationId,
        direction,
        body,
        status: direction == 'out' ? 'sent' : '',
        createdAt: createdAt,
      );
      created++;

      // Track unread
      if (direction == 'in') {
        final isRead = nativeRead is int ? nativeRead == 1 : true;
        if (!isRead) {
          convHasUnread[conversationId] = true;
        }
      }

      // Report progress every 20 items or at the end
      if (i % 20 == 0 || i == total - 1) {
        onProgress?.call(i + 1, total);
      }
    }

    // Mark conversations with unread incoming messages
    for (final entry in convHasUnread.entries) {
      await convRepo.markUnread(entry.key);
    }

    onProgress?.call(total, total);
    debugPrint('[SmsGo] importAll: created=$created skipped=$skipped unread=${convHasUnread.length}');
  }
}

