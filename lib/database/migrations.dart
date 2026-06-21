import 'package:sqflite/sqflite.dart';

class Migrations {
  static const int currentVersion = 19;



  static Future<void> onCreate(Database db, int version) async {
    await _createCampaignsTable(db);
    await _createLeadsTable(db);
    await _createNotesTable(db);
    await _createNoteGroupsTable(db);
    await _createSendingSessionsTable(db);
    await _createRepliesTable(db);
    await _createSendLogsTable(db);
    await _createMonitorNumbersTable(db);
    await _createConversationsTable(db);
    await _createConversationMessagesTable(db);
    await _createIndexes(db);
  }

  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE sending_sessions ADD COLUMN send_interval_min INTEGER DEFAULT 3');
      await db.execute('ALTER TABLE sending_sessions ADD COLUMN send_interval_max INTEGER DEFAULT 3');
      await db.execute('ALTER TABLE sending_sessions ADD COLUMN rest_enabled INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE sending_sessions ADD COLUMN rest_seconds INTEGER DEFAULT 0');
    }

    if (oldVersion < 3) {
      await db.execute('ALTER TABLE sending_sessions ADD COLUMN paused INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE sending_sessions ADD COLUMN next_send_at TEXT');
    }

    // Add conversations storage and messages (v5)
    if (oldVersion < 5) {
      await _createConversationsTable(db);
      await _createConversationMessagesTable(db);
      await db.execute('CREATE INDEX IF NOT EXISTS idx_conversations_session ON conversations(session_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_conversation ON conversation_messages(conversation_id)');
    }

    // v6: add status column for outgoing message state (sending/sent/failed)
    if (oldVersion < 6) {
      await db.execute("ALTER TABLE conversation_messages ADD COLUMN status TEXT NOT NULL DEFAULT 'sent'");
    }

    // v7: add unread column for conversation read/unread tracking
    if (oldVersion < 7) {
      await db.execute("ALTER TABLE conversations ADD COLUMN unread INTEGER NOT NULL DEFAULT 0");
    }

    // v8: make session_id nullable in conversations (imported/direct conversations don't need a session)
    // v9: retry v8 migration if it failed previously
    if (oldVersion < 9) {
      try {
        // Check if session_id is still NOT NULL by testing an insert
        final test = await db.rawQuery("SELECT sql FROM sqlite_master WHERE type='table' AND name='conversations'");
        final createSql = test.isNotEmpty ? (test.first['sql'] as String? ?? '') : '';
        if (createSql.contains('session_id INTEGER NOT NULL')) {
          // Table still has NOT NULL — redo the migration
          await db.execute('PRAGMA foreign_keys = OFF');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS conversations_new(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id INTEGER,
              lead_id INTEGER,
              phone_number TEXT NOT NULL,
              last_message TEXT,
              replied INTEGER DEFAULT 0,
              unread INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('DELETE FROM conversations_new');
          await db.execute('INSERT INTO conversations_new SELECT * FROM conversations');
          await db.execute('DROP TABLE IF EXISTS conversations');
          await db.execute('ALTER TABLE conversations_new RENAME TO conversations');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_conversations_session ON conversations(session_id)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_conversation ON conversation_messages(conversation_id)');
          await db.execute('PRAGMA foreign_keys = ON');
        }
      } catch (e) {
        // If migration still fails, we'll handle NULL session_id at the app level
        try { await db.execute('PRAGMA foreign_keys = ON'); } catch (_) {}
      }
    }

    // v10: normalize all phone numbers and merge duplicate conversations
    if (oldVersion < 10) {
      await _normalizeAndMergeConversations(db);
    }

    // v11: add group_name column to notes table for grouping
    if (oldVersion < 11) {
      await db.execute("ALTER TABLE notes ADD COLUMN group_name TEXT NOT NULL DEFAULT ''");
    }

    // v12: add note_groups table for persistent groups
    if (oldVersion < 12) {
      await _createNoteGroupsTable(db);
    }

    // v13: add rest_after_count and selected_groups to sending_sessions
    if (oldVersion < 13) {
      await db.execute("ALTER TABLE sending_sessions ADD COLUMN rest_after_count INTEGER NOT NULL DEFAULT 0");
      await db.execute("ALTER TABLE sending_sessions ADD COLUMN selected_groups TEXT NOT NULL DEFAULT ''");
    }

    // v14: add progress_notify_after to sending_sessions
    if (oldVersion < 14) {
      await db.execute("ALTER TABLE sending_sessions ADD COLUMN progress_notify_after INTEGER NOT NULL DEFAULT 15");
    }

    // v15: add campaign_id to conversations for campaign-level deduplication
    if (oldVersion < 15) {
      await db.execute("ALTER TABLE conversations ADD COLUMN campaign_id INTEGER");
      await db.execute('CREATE INDEX IF NOT EXISTS idx_conversations_campaign ON conversations(campaign_id)');
      // Backfill campaign_id from sending_sessions for existing session-based conversations
      await db.execute('''
        UPDATE conversations SET campaign_id = (
          SELECT ss.campaign_id FROM sending_sessions ss WHERE ss.id = conversations.session_id
        ) WHERE session_id IS NOT NULL
      ''');
    }

    if (oldVersion < 16) {
      await db.execute("ALTER TABLE conversation_messages ADD COLUMN sim_slot TEXT");
    }

    // v17: add session_id to conversation_messages for per-session message tracking
    if (oldVersion < 17) {
      await db.execute("ALTER TABLE conversation_messages ADD COLUMN session_id INTEGER");
      await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_session ON conversation_messages(session_id)');
      // Backfill session_id from conversations table
      await db.execute('''
        UPDATE conversation_messages SET session_id = (
          SELECT c.session_id FROM conversations c WHERE c.id = conversation_messages.conversation_id
        ) WHERE session_id IS NULL
      ''');
    }

    // v18: normalize network 'Dito' -> 'DITO'
    if (oldVersion < 18) {
      await db.execute("UPDATE leads SET network = 'DITO' WHERE network = 'Dito'");
    }

    // v19: add performance indexes for hot paths
    if (oldVersion < 19) {
      await _createPerformanceIndexes(db);
    }
  }



  static Future<void> _createCampaignsTable(Database db) async {
    await db.execute('''
      CREATE TABLE campaigns(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        total_leads INTEGER DEFAULT 0,
        sent_count INTEGER DEFAULT 0,
        failed_count INTEGER DEFAULT 0,
        completed INTEGER DEFAULT 0,
        archived INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createLeadsTable(Database db) async {
    await db.execute('''
      CREATE TABLE leads(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        campaign_id INTEGER NOT NULL,
        name TEXT,
        phone_number TEXT NOT NULL,
        network TEXT NOT NULL DEFAULT 'Others',
        sent INTEGER DEFAULT 0,
        failed INTEGER DEFAULT 0,
        replied INTEGER DEFAULT 0,
        reply_message TEXT,
        sent_at TEXT,
        FOREIGN KEY(campaign_id) REFERENCES campaigns(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _createNotesTable(Database db) async {
    await db.execute('''
      CREATE TABLE notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        content TEXT NOT NULL,
        group_name TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createNoteGroupsTable(Database db) async {
    await db.execute('''
      CREATE TABLE note_groups(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createSendingSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE sending_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        campaign_id INTEGER NOT NULL,
        sim_slot TEXT NOT NULL DEFAULT 'SIM 1',
        target_network TEXT NOT NULL DEFAULT 'All',
        message_mode TEXT NOT NULL DEFAULT 'rotational',
        total_targets INTEGER DEFAULT 0,
        sent_count INTEGER DEFAULT 0,
        failed_count INTEGER DEFAULT 0,
        running INTEGER DEFAULT 1,
        send_interval INTEGER DEFAULT 3,
        send_interval_min INTEGER DEFAULT 3,
        send_interval_max INTEGER DEFAULT 3,
        rest_enabled INTEGER DEFAULT 0,
        rest_seconds INTEGER DEFAULT 0,
        rest_after_count INTEGER NOT NULL DEFAULT 0,
        progress_notify_after INTEGER NOT NULL DEFAULT 15,
        selected_groups TEXT NOT NULL DEFAULT '',
        monitor_number TEXT,
        paused INTEGER DEFAULT 0,
        next_send_at TEXT,
        created_at TEXT NOT NULL,
        ended_at TEXT
      )
    ''');
  }

  static Future<void> _createConversationsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        campaign_id INTEGER,
        lead_id INTEGER,
        phone_number TEXT NOT NULL,
        last_message TEXT,
        replied INTEGER DEFAULT 0,
        unread INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES sending_sessions(id) ON DELETE SET NULL,
        FOREIGN KEY(lead_id) REFERENCES leads(id) ON DELETE SET NULL
      )
    ''');
  }

  static Future<void> _createConversationMessagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversation_messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id INTEGER NOT NULL,
        session_id INTEGER,
        direction TEXT NOT NULL,
        message TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'sent',
        sim_slot TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
  }


  static Future<void> _createRepliesTable(Database db) async {
    await db.execute('''
      CREATE TABLE replies(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lead_id INTEGER,
        phone_number TEXT NOT NULL,
        message TEXT NOT NULL,
        received_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createSendLogsTable(Database db) async {
    await db.execute('''
      CREATE TABLE send_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        lead_id INTEGER,
        phone_number TEXT NOT NULL,
        message TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createMonitorNumbersTable(Database db) async {
    await db.execute('''
      CREATE TABLE monitor_numbers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phone_number TEXT NOT NULL UNIQUE,
        label TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX idx_leads_campaign ON leads(campaign_id)');
    await db.execute('CREATE INDEX idx_leads_phone ON leads(phone_number)');
    await db.execute('CREATE INDEX idx_leads_network ON leads(network)');
    await db.execute('CREATE INDEX idx_logs_session ON send_logs(session_id)');
    await db.execute('CREATE INDEX idx_replies_phone ON replies(phone_number)');
    await _createPerformanceIndexes(db);
  }

  static Future<void> _createPerformanceIndexes(Database db) async {
    // Leads: composite indexes for filtering by campaign + status
    await db.execute('CREATE INDEX IF NOT EXISTS idx_leads_campaign_sent ON leads(campaign_id, sent)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_leads_campaign_network ON leads(campaign_id, network)');

    // Conversations: composite indexes for common queries
    await db.execute('CREATE INDEX IF NOT EXISTS idx_conv_campaign_phone ON conversations(campaign_id, phone_number)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_conv_session_unread ON conversations(session_id, unread)');

    // Conversation messages: composite index for status subqueries
    await db.execute('CREATE INDEX IF NOT EXISTS idx_msg_conv_dir_created ON conversation_messages(conversation_id, direction, created_at)');

    // Notes: index for group queries
    await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_group ON notes(group_name)');

    // Sending sessions: index for campaign lookups
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_campaign ON sending_sessions(campaign_id)');
  }

  /// Normalize all phone numbers in conversations table and merge duplicates.
  static Future<void> _normalizeAndMergeConversations(Database db) async {
    String normalizePhone(String phone) {
      var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 7) return phone.trim();
      if (digits.startsWith('63') && digits.length >= 11) {
        digits = '0' + digits.substring(2);
      }
      if (digits.length >= 10 && digits.startsWith('9')) {
        digits = '0' + digits;
      }
      return digits;
    }

    try {
      final rows = await db.query('conversations');
      final Map<String, List<Map<String, dynamic>>> grouped = {};

      for (final row in rows) {
        final phone = (row['phone_number'] as String? ?? '');
        final normalized = normalizePhone(phone);
        grouped.putIfAbsent(normalized, () => []).add(row);
      }

      for (final entry in grouped.entries) {
        final normalized = entry.key;
        final convs = entry.value;
        if (convs.length <= 1) {
          // Single conversation — just normalize the phone number if needed
          final id = convs.first['id'] as int;
          final currentPhone = convs.first['phone_number'] as String? ?? '';
          if (currentPhone != normalized) {
            await db.update('conversations', {'phone_number': normalized}, where: 'id = ?', whereArgs: [id]);
          }
          continue;
        }

        // Multiple conversations with same normalized phone — merge into oldest
        convs.sort((a, b) => (a['created_at'] as String).compareTo(b['created_at'] as String));
        final keepId = convs.first['id'] as int;

        // Normalize the kept conversation's phone number
        await db.update('conversations', {'phone_number': normalized}, where: 'id = ?', whereArgs: [keepId]);

        // Move messages from duplicates to the kept conversation
        for (int i = 1; i < convs.length; i++) {
          final dupId = convs[i]['id'] as int;
          await db.update(
            'conversation_messages',
            {'conversation_id': keepId},
            where: 'conversation_id = ?',
            whereArgs: [dupId],
          );
          await db.delete('conversation_messages', where: 'conversation_id = ? AND conversation_id != ?', whereArgs: [dupId, keepId]);
          await db.delete('conversations', where: 'id = ?', whereArgs: [dupId]);
        }

        // Update last_message on the kept conversation
        final lastMsg = await db.rawQuery(
          'SELECT message FROM conversation_messages WHERE conversation_id = ? ORDER BY created_at DESC LIMIT 1',
          [keepId],
        );
        if (lastMsg.isNotEmpty) {
          await db.update('conversations', {'last_message': lastMsg.first['message']}, where: 'id = ?', whereArgs: [keepId]);
        }
      }
    } catch (e) {
      // Log but don't crash — app can still function without merged conversations
      print('WARNING: _normalizeAndMergeConversations failed: $e');
    }
  }
}
