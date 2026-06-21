import 'package:flutter/foundation.dart';
import '../database/database.dart';
import '../models/conversation.dart';
import '../repositories/conversation_repository.dart';

class ImportedConversations {
  final List<Conversation> active;
  final List<Conversation> others;

  ImportedConversations({
    required this.active,
    required this.others,
  });
}

/// Provides imported conversations partitioned into:
/// - active: conversations whose phone number matches a lead of the campaign owning this session
/// - others: everything else
///
/// Note: current schema stores conversation.session_id but does not store
/// a distinct "imported" marker. We approximate by selecting conversations
/// that belong to an existing session (the session passed in).
class ImportedConversationsProvider extends ChangeNotifier {
  final int sessionId;

  final _db = AppDatabase.instance;
  bool _loading = false;
  bool get loading => _loading;

  ImportedConversations? _data;
  ImportedConversations? get data => _data;

  ImportedConversationsProvider(this.sessionId);

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    final db = await _db.database;
    final convRepo = ConversationRepository(db);

    // Load all conversations for the session.
    final convs = await convRepo.getConversationsForSession(sessionId);

    // Load campaign lead phone numbers to decide Active vs Others.
    final sess = await db.query(
      'sending_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    final campaignId = sess.isNotEmpty ? sess.first['campaign_id'] as int? : null;

    final leadPhones = <String>{};
    if (campaignId != null) {
      final leads = await db.query(
        'leads',
        where: 'campaign_id = ?',
        whereArgs: [campaignId],
      );
      for (final l in leads) {
        final p = (l['phone_number'] as String?)?.trim();
        if (p != null && p.isNotEmpty) leadPhones.add(p);
      }
    }

    final active = <Conversation>[];
    final others = <Conversation>[];

    for (final c in convs) {
      if (leadPhones.contains(c.phoneNumber)) {
        active.add(c);
      } else {
        others.add(c);
      }
    }

    _data = ImportedConversations(active: active, others: others);
    _loading = false;
    notifyListeners();
  }
}

