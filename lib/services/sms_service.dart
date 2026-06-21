import 'dart:async';
import 'dart:math';
import '../models/lead.dart';
import '../models/note.dart';
import '../models/sending_session.dart';
import '../repositories/lead_repository.dart';
import '../repositories/campaign_repository.dart';
import '../repositories/sending_session_repository.dart';


import 'sms_gateway.dart';
import '../database/database.dart';
import '../repositories/conversation_repository.dart';

typedef OnSendProgress = void Function(int sent, int failed, int total, {String lastMessage, int dispatched});

class SmsService {
  static SmsService? _instance;
  static SmsService get instance => _instance ??= SmsService._();
  SmsService._() {
    _registerInboundListener();
    _syncPendingNativeReplies();
    _listenForSendResults();
  }

  // Broadcast stream for per-send events (phone/status)
  final _sendEventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get sendEvents => _sendEventController.stream;

  /// Emit a send event for UI consumers (e.g. from ActiveSendProvider.sendReply)
  void emitSendEvent(Map<String, dynamic> event) {
    try {
      _sendEventController.add(event);
    } catch (_) {}
  }

  // Broadcast stream for incoming SMS events (phone/message/conversationId)
  final _incomingEventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incomingEvents => _incomingEventController.stream;

  final _simController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get simStream => _simController.stream;

  StreamSubscription<Map<String, dynamic>>? _sendResultSub;

  bool get isListeningForSendResults => _sendResultSub != null;

  void _syncPendingNativeReplies() {
    // Fire-and-forget: fetch pending replies persisted by native receiver and process them.
    // fromSync=true — these already showed a native notification, so don't re-notify via Flutter.
    Future.microtask(() async {
      try {
        final pending = await SmsGateway.getPendingNativeReplies();
        if (pending == null) return;
        for (final item in pending) {
          try {
            final map = Map<String, dynamic>.from(item as Map);
            await handleIncomingSms(map, fromSync: true);
            final idRaw = map['id'];
            int? id;
            if (idRaw is int) id = idRaw;
            if (idRaw is double) id = idRaw.toInt();
            if (id != null) {
              await SmsGateway.deleteNativeReply(id);
            }
          } catch (e) {
            // ignore per-item errors
          }
        }
      } catch (e) {
        // ignore
      }
    });
  }

  void _listenForSendResults() {
    _sendResultSub = SmsGateway.sendResults.listen((result) async {
      try {
        final phoneRaw = (result['phone'] ?? '') as String;
        final phone = normalizePhone(phoneRaw);
        final success = result['success'] == true;

        final db = await AppDatabase.instance.database;
        final convRepo = ConversationRepository(db);

        final convRows = await db.query(
          'conversations',
          where: 'phone_number = ?',
          whereArgs: [phone],
          orderBy: 'created_at DESC',
          limit: 1,
        );

        if (convRows.isEmpty) return;
        final convId = convRows.first['id'] as int?;
        if (convId == null) return;

        // Get sessionId: first try session_id on conversation, then fall back to active session via campaign_id
        var sessionId = convRows.first['session_id'] as int?;
        if (sessionId == null) {
          final campaignId = convRows.first['campaign_id'] as int?;
          if (campaignId != null) {
            final sessionRows = await db.query(
              'sending_sessions',
              where: 'campaign_id = ? AND running = 1',
              whereArgs: [campaignId],
              orderBy: 'created_at DESC',
              limit: 1,
            );
            if (sessionRows.isNotEmpty) {
              sessionId = sessionRows.first['id'] as int?;
            }
          }
        }

        // Find the latest outgoing message with status 'sending'
        final msgRows = await db.query(
          'conversation_messages',
          where: 'conversation_id = ? AND direction = ? AND status = ?',
          whereArgs: [convId, 'out', 'sending'],
          orderBy: 'created_at DESC',
          limit: 1,
        );

        if (msgRows.isNotEmpty) {
          final msgId = msgRows.first['id'] as int?;
          if (msgId != null) {
            final newStatus = success ? 'sent' : 'failed';
            await convRepo.updateMessageStatus(msgId, newStatus);

            // Get session_id from the message itself (per-session accuracy)
            final msgSessionId = msgRows.first['session_id'] as int?;

            // If no session_id on message, fall back to conversation's session_id
            final effectiveSessionId = msgSessionId ?? sessionId;

            // Update sending_sessions counts so loadActiveSessions reads fresh data
            if (effectiveSessionId != null) {
              final counts = await _queryActualCounts(db, effectiveSessionId);
              await db.update('sending_sessions', {
                'sent_count': counts['sent'],
                'failed_count': counts['failed'],
              }, where: 'id = ?', whereArgs: [effectiveSessionId]);
            }

            // Update campaign counts (unique sent/failed contacts)
            final campaignId = convRows.first['campaign_id'] as int?;
            if (campaignId != null) {
              await _campaignRepo.updateCounts(campaignId);
            }

            // Emit event with actual session id so ActiveSendProvider can handle it
            _sendEventController.add({
              'phone': phone,
              'success': success,
              'sessionId': effectiveSessionId,
              'status': newStatus,
            });
          }
        }
      } catch (_) {}
    });
  }

  // register native inbound SMS listener
  void _registerInboundListener() {
    SmsGateway.startListening((payload) async {
      try {
        await handleIncomingSms(payload);
      } catch (_) {
        // swallow errors from inbound handling to avoid crashing native callbacks
      }
    }, onSim: (simPayload) async {
      try {
        _simController.add(simPayload);
      } catch (_) {
        // ignore
      }
    });
  }

  Future<void> handleIncomingSms(Map<String, dynamic> payload, {bool fromSync = false}) async {
    final fromRaw = (payload['from'] ?? payload['address'] ?? payload['phone_number'])?.toString() ?? '';
    final from = normalizePhone(fromRaw);
    final message = ((payload['message'] ?? '') as String).trim();
    final receivedAt = (payload['receivedAt'] as String?) ?? DateTime.now().toIso8601String();
    final simSlot = (payload['simSlot'] as String?) ?? '';

    final db = await AppDatabase.instance.database;

    // Insert into replies table for historical records
    await db.insert('replies', {
      'lead_id': null,
      'phone_number': from,
      'message': message,
      'received_at': receivedAt,
    });

    // Mark lead replied if exists
    await _leadRepo.markReplied(from, message);

    // Attach to conversation if we can find / create a session-based conversation
    final convRepo = ConversationRepository(db);

    // (A) Attach to the most recently created conversation for this phone number (across sessions)
    // Search by both normalized and raw number (handles named senders like "SSS NDRRMC")
    final existing = await db.rawQuery(
      "SELECT * FROM conversations WHERE phone_number = ? OR phone_number = ? ORDER BY created_at DESC LIMIT 1",
      [from, fromRaw],
    );

    int? convId;
    int? campaignSessionId;
    if (existing.isNotEmpty) {
      convId = existing.first['id'] as int?;
      final existingSessionId = existing.first['session_id'] as int?;
      final existingCampaignId = existing.first['campaign_id'] as int?;
      if (existingCampaignId != null) {
        final sessionRows = await db.query(
          'sending_sessions',
          where: 'campaign_id = ? AND running = 1',
          whereArgs: [existingCampaignId],
          orderBy: 'created_at DESC',
          limit: 1,
        );
        if (sessionRows.isNotEmpty) {
          campaignSessionId = sessionRows.first['id'] as int?;
          // Re-associate conversation with active session if it was orphaned
          if (existingSessionId == null && campaignSessionId != null) {
            await db.update(
              'conversations',
              {'session_id': campaignSessionId},
              where: 'id = ?',
              whereArgs: [convId],
            );
          }
        } else {
          // No active session for this campaign — move conversation to Imported Messages
          if (existingSessionId != null) {
            await db.update(
              'conversations',
              {'session_id': null},
              where: 'id = ?',
              whereArgs: [convId],
            );
          }
        }
      }
    } else {
      // Try to find lead + session for this number
      final leadRows = await db.query(
        'leads',
        where: 'phone_number = ?',
        whereArgs: [from],
        limit: 1,
      );

      if (leadRows.isNotEmpty) {
        final lead = leadRows.first;
        final campaignId = lead['campaign_id'] as int?;

        if (campaignId != null) {
          final sessionRows = await db.query(
            'sending_sessions',
            where: 'campaign_id = ? AND running = 1',
            whereArgs: [campaignId],
            orderBy: 'created_at DESC',
            limit: 1,
          );

          if (sessionRows.isNotEmpty) {
            final sessionId = sessionRows.first['id'] as int;
            campaignSessionId = sessionId;
            convId = await convRepo.createConversation(
              sessionId,
              from,
              leadId: lead['id'] as int?,
              campaignId: campaignId,
            );
          }
        }
      }

      // Fallback: create a standalone conversation (no campaign/session)
      // This ensures incoming SMS from ANY number is always captured
      if (convId == null) {
        convId = await convRepo.createConversation(null, from);
      }
    }

    if (convId != null) {
      // Dedup check — prevent duplicate messages from reprocessing (e.g. _syncPendingNativeReplies)
      final dupCheck = await db.rawQuery(
        "SELECT id FROM conversation_messages WHERE conversation_id = ? AND direction = ? AND TRIM(message) = TRIM(?) LIMIT 1",
        [convId, 'in', message],
      );
      if (dupCheck.isNotEmpty) return;

      await convRepo.addMessage(convId, 'in', message, simSlot: simSlot.isNotEmpty ? simSlot : null, sessionId: campaignSessionId);
      await convRepo.markUnread(convId);

      // Emit incoming event for real-time UI consumers and notifications
      // Skip notification when fromSync (native already showed one when app was killed)
      if (!fromSync) {
        try {
          _incomingEventController.add({
            'phone': from,
            'message': message,
            'conversationId': convId,
            'receivedAt': receivedAt,
          });
      } catch (e) {
        print('WARNING: _listenForSendResults failed: $e');
      }
      }
    }
  }





  final _leadRepo = LeadRepository();
  final _sessionRepo = SendingSessionRepository();
  final _campaignRepo = CampaignRepository();
  final _random = Random();

  // Flutter MethodChannel bridge
  // (SmsGateway methods are static)




  // Active sessions: sessionId -> Timer
  final Map<int, Timer> _timers = {};

  // sequential tracking: sessionId -> index into message list
  final Map<int, int> _msgIndex = {};

  // Shared send loops for resume/pause.
  final Map<int, Future<void> Function()> _sendLoops = {};

  // Failure timeout timers (separate from send timers)
  final Map<int, Timer> _timeoutTimers = {};


  bool isRunning(int sessionId) => _timers.containsKey(sessionId);



  int _simSlotToIndex(String simSlot) {
    // Your UI uses: "SIM 1", "SIM 2", "Both"
    if (simSlot == 'SIM 2') return 1;
    if (simSlot == 'Both') return _bothSimCounter++ % 2;
    return 0;
  }

  int _bothSimCounter = 0;

  Future<int> startSession({
    required SendingSession session,
    required List<Note> messages,
    required List<Lead> targets,
    OnSendProgress? onProgress,
    void Function(int sessionId)? onSessionCreated,
  }) async {
    // Insert session record
    final sessionId = await _sessionRepo.create(
      session.copyWith(
        totalTargets: targets.length,
        createdAt: DateTime.now().toIso8601String(),
      ),
    );

    // Notify caller of session ID immediately so it can track progress
    onSessionCreated?.call(sessionId);

    _msgIndex[sessionId] = 0;
    int sent = 0;
    int failed = 0;
    int idx = 0;

    // Conversation repo for creating conversations during send
    final db = await AppDatabase.instance.database;
    final convRepo = ConversationRepository(db);

    // Create ALL conversations upfront so they appear immediately in the UI
    final conversationMap = <String, int>{}; // phoneNumber -> conversationId
    for (final lead in targets) {
      final existingConv = await db.query(
        'conversations',
        where: 'campaign_id = ? AND phone_number = ?',
        whereArgs: [session.campaignId, lead.phoneNumber],
        limit: 1,
      );
      if (existingConv.isNotEmpty) {
        conversationMap[lead.phoneNumber] = existingConv.first['id'] as int;
      } else {
        final convId = await convRepo.createConversation(
          sessionId,
          lead.phoneNumber,
          leadId: lead.id,
          campaignId: session.campaignId,
        );
        conversationMap[lead.phoneNumber] = convId;
      }
    }

    late void Function() scheduleNext;

    Future<void> sendNext() async {
      if (idx >= targets.length) {
        // Query actual counts from DB before completing
        final finalCounts = await _queryActualCounts(db, sessionId);
        sent = finalCounts['sent']!;
        failed = finalCounts['failed']!;
        // Save final counts to session DB
        await db.update('sending_sessions', {
          'sent_count': sent,
          'failed_count': failed,
          'total_targets': targets.length,
        }, where: 'id = ?', whereArgs: [sessionId]);

        // Update campaign counts on completion
        await _campaignRepo.updateCounts(session.campaignId);

        _timers.remove(sessionId);
        _msgIndex.remove(sessionId);
        stopFailureTimeout(sessionId);
        await _sessionRepo.stop(sessionId);
        onProgress?.call(sent, failed, targets.length, lastMessage: '', dispatched: targets.length);
        // Emit completion event
        try {
          _sendEventController.add({
            "phone": "",
            "success": true,
            "sessionId": sessionId,
            "completed": true,
          });
        } catch (_) {}
        return;
      }

      final lead = targets[idx];
      idx++;

      // Select message using idx (target index) for rotation — not `sent` which is
      // optimistic and may not reflect actual delivery status.
      final msgIdx = session.messageMode == 'sequential'
          ? (_msgIndex[sessionId]! % messages.length)
          : (idx % messages.length);
      var message = messages[msgIdx].content;
      if (session.messageMode == 'sequential') {
        _msgIndex[sessionId] = _msgIndex[sessionId]! + 1;
      }

      // Replace {username} placeholder with lead name
      final leadName = lead.name ?? '';
      message = message.replaceAll('{username}', leadName);

      // Get pre-created conversation for this lead
      final convId = conversationMap[lead.phoneNumber];

      // Add outgoing message with 'sending' status
      int? msgDbId;
      if (convId != null) {
        msgDbId = await convRepo.addMessage(convId, 'out', message, status: 'sending', simSlot: session.simSlot, sessionId: sessionId);
      }

      // Emit 'sending' event so UI shows real-time status immediately
      try {
        _sendEventController.add({
          "phone": lead.phoneNumber,
          "success": null,
          "sessionId": sessionId,
          "status": "sending",
        });
      } catch (_) {}

      // Give UI time to rebuild and show the hourglass icon before sendSms returns
      await Future.delayed(const Duration(milliseconds: 250));

      bool sendAccepted = false;
      try {
        await SmsGateway.sendSms(
          to: lead.phoneNumber,
          message: message,
          simSlot: _simSlotToIndex(session.simSlot),
        );
        sendAccepted = true;
      } catch (_) {
        sendAccepted = false;
      }

      // If sendSms threw a platform exception, mark as failed immediately.
      // Otherwise, SentReceiver will update the status to 'sent' or 'failed'.
      if (!sendAccepted) {
        if (msgDbId != null) {
          await convRepo.updateMessageStatus(msgDbId, 'failed');
        }
        try {
          _sendEventController.add({
            "phone": lead.phoneNumber,
            "success": false,
            "sessionId": sessionId,
            "status": "failed",
          });
        } catch (_) {}
      }

      // Query DB for actual sent/failed counts (source of truth from conversation_messages)
      final actualCounts = await _queryActualCounts(db, sessionId);
      sent = actualCounts['sent']!;
      failed = actualCounts['failed']!;

      await _sessionRepo.update(
        session.copyWith(id: sessionId, sentCount: sent, failedCount: failed, totalTargets: targets.length),
      );

      onProgress?.call(sent, failed, targets.length, lastMessage: message, dispatched: idx);

      // Send progress SMS to monitor number after N messages
      if (session.progressNotifyAfter > 0 &&
          session.monitorNumber != null &&
          session.monitorNumber!.isNotEmpty &&
          sent > 0 &&
          sent % session.progressNotifyAfter == 0) {
        final progressMsg = 'Sent $sent: $message';
        try {
          await SmsGateway.sendSms(
            to: session.monitorNumber!,
            message: progressMsg,
            simSlot: _simSlotToIndex(session.simSlot),
          );
        } catch (_) {
          // Don't fail the session if progress notification fails
        }
      }

      scheduleNext();
    }

    scheduleNext = () {
      final intervalMin = min(session.sendIntervalMin, session.sendIntervalMax);
      final intervalMax = max(session.sendIntervalMin, session.sendIntervalMax);
      final interval = intervalMin + _random.nextInt(intervalMax - intervalMin + 1);

      // Rest logic: restAfterCount takes priority (rest after N sends),
      // otherwise if restEnabled, rest after every send.
      int rest = 0;
      if (session.restEnabled && session.restSeconds > 0) {
        if (session.restAfterCount > 0) {
          // Rest only after every N sends
          if (idx > 0 && idx % session.restAfterCount == 0) {
            rest = session.restSeconds;
          }
        } else {
          // Rest after every send
          rest = session.restSeconds;
        }
      }

      // Emit rest event if resting
      if (rest > 0) {
        try {
          _sendEventController.add({
            "phone": "",
            "success": true,
            "sessionId": sessionId,
            "resting": true,
            "restSeconds": rest,
          });
        } catch (_) {}
      }

      // Emit countdown info so UI can show timer
      final totalWait = interval + rest;
      final nextSendAt = DateTime.now().add(Duration(seconds: totalWait)).toIso8601String();
      try {
        _sendEventController.add({
          "phone": "",
          "success": true,
          "sessionId": sessionId,
          "countdown": true,
          "intervalSeconds": interval,
          "restSeconds": rest,
          "nextSendAt": nextSendAt,
          "totalWait": totalWait,
        });
      } catch (_) {}

      _timers[sessionId] = Timer(Duration(seconds: totalWait), () async {
        // Emit rest complete event
        if (rest > 0) {
          try {
            _sendEventController.add({
              "phone": "",
              "success": true,
              "sessionId": sessionId,
              "resting": false,
            });
          } catch (_) {}
        }
        // Prevent auto-send after pause (handles race where timer fired right before pause()).
        final rows = await db.query(
          'sending_sessions',
          where: 'id = ?',
          whereArgs: [sessionId],
          limit: 1,
        );
        final paused = rows.isNotEmpty ? (rows.first['paused'] ?? 0) == 1 : false;
        if (paused) return;
        await sendNext();
      });
    };


    // Store the in-memory resume loop.
    _sendLoops[sessionId] = () async {
      if (idx >= targets.length) return;
      scheduleNext();
    };

    scheduleNext();

    // Start failure timeout for messages stuck in 'sending'
    startFailureTimeout(sessionId);

    return sessionId;

  }

  Future<void> pauseSession(int sessionId) async {
    // Proper pause: stop the timer loop immediately and mark paused in DB.
    _timers[sessionId]?.cancel();
    _timers.remove(sessionId);

    final now = DateTime.now();
    await _sessionRepo.pause(sessionId, nextSendAtIso: now.toIso8601String());
  }

  Future<void> resumeSession(int sessionId) async {
    // Mark DB state first.
    final now = DateTime.now();
    await _sessionRepo.resume(sessionId, nextSendAtIso: now.toIso8601String());

    // Resume the in-memory timer loop (only works if this session was started in the current runtime).
    final loop = _sendLoops[sessionId];
    if (loop == null) return;

    // If a timer already exists, don't duplicate.
    if (_timers.containsKey(sessionId)) return;

    await loop();

  }





  Future<void> stopSession(int sessionId) async {
    // Save current counts before stopping
    final db = await AppDatabase.instance.database;
    final actualCounts = await _queryActualCounts(db, sessionId);
    await db.update('sending_sessions', {
      'sent_count': actualCounts['sent'],
      'failed_count': actualCounts['failed'],
    }, where: 'id = ?', whereArgs: [sessionId]);

    // Get campaign_id from session to update campaign counts
    final sessRows = await db.query('sending_sessions', where: 'id = ?', whereArgs: [sessionId], limit: 1);
    if (sessRows.isNotEmpty) {
      final campaignId = sessRows.first['campaign_id'] as int?;
      if (campaignId != null) {
        await _campaignRepo.updateCounts(campaignId);
      }
    }

    _timers[sessionId]?.cancel();
    stopFailureTimeout(sessionId);
    _timers.remove(sessionId);
    _msgIndex.remove(sessionId);
    _sendLoops.remove(sessionId);
    await _sessionRepo.stop(sessionId);
  }


  void stopAll() {
    for (final t in _timers.values) {
      t.cancel();
    }
    for (final t in _timeoutTimers.values) {
      t.cancel();
    }
    _timers.clear();
    _timeoutTimers.clear();
    _msgIndex.clear();
    _sendLoops.clear();
  }

  /// Query actual sent/failed counts from conversation_messages for a session.
  Future<Map<String, int>> _queryActualCounts(dynamic db, int sessionId) async {
    try {
      final rows = await db.rawQuery('''
        SELECT
          cm.status,
          COUNT(*) as cnt
        FROM conversation_messages cm
        WHERE cm.session_id = ? AND cm.direction = 'out'
        GROUP BY cm.status
      ''', [sessionId]);
      int sent = 0;
      int failed = 0;
      for (final row in rows) {
        final status = row['status'] as String?;
        final cnt = row['cnt'] as int? ?? 0;
        if (status == 'sent') sent = cnt;
        if (status == 'failed') failed = cnt;
      }
      return {'sent': sent, 'failed': failed};
    } catch (_) {
      return {'sent': 0, 'failed': 0};
    }
  }

  /// Start failure timeout: periodically check for messages stuck in 'sending'
  /// and mark them as 'failed' after the timeout period.
  void startFailureTimeout(int sessionId, {Duration timeout = const Duration(minutes: 3)}) {
    _timeoutTimers[sessionId]?.cancel();
    _timeoutTimers[sessionId] = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final db = await AppDatabase.instance.database;
        final cutoff = DateTime.now().subtract(timeout).toIso8601String();
        // Find outgoing messages stuck in 'sending' that were created before the cutoff
        final stuck = await db.rawQuery('''
          SELECT cm.id
          FROM conversation_messages cm
          WHERE cm.session_id = ?
            AND cm.direction = 'out' AND cm.status = 'sending'
            AND cm.created_at < ?
        ''', [sessionId, cutoff]);
        for (final row in stuck) {
          final msgId = row['id'] as int;
          await db.update('conversation_messages', {'status': 'failed'}, where: 'id = ?', whereArgs: [msgId]);
          // Find the conversation to emit event
          final msgConv = await db.rawQuery(
            'SELECT conversation_id FROM conversation_messages WHERE id = ?',
            [msgId],
          );
          if (msgConv.isNotEmpty) {
            final convId = msgConv.first['conversation_id'] as int;
            final convRows = await db.query('conversations', where: 'id = ?', whereArgs: [convId], limit: 1);
            if (convRows.isNotEmpty) {
              final phone = convRows.first['phone_number'] as String? ?? '';
              try {
                _sendEventController.add({
                  'phone': phone,
                  'success': false,
                  'sessionId': sessionId,
                  'status': 'failed',
                });
              } catch (_) {}
            }
          }
        }
        // Update session counts after timeout fixes
        if (stuck.isNotEmpty) {
          final actualCounts = await _queryActualCounts(db, sessionId);
          final sessRows = await db.query('sending_sessions', where: 'id = ?', whereArgs: [sessionId], limit: 1);
          if (sessRows.isNotEmpty) {
            await db.update('sending_sessions', {
              'sent_count': actualCounts['sent'],
              'failed_count': actualCounts['failed'],
            }, where: 'id = ?', whereArgs: [sessionId]);
          }
          // Notify messaging provider to reload
          try {
            _sendEventController.add({
              'phone': '',
              'success': false,
              'sessionId': sessionId,
              'status': 'timeout_updated',
            });
          } catch (_) {}
        }
      } catch (_) {}
    });
  }

  void stopFailureTimeout(int sessionId) {
    _timeoutTimers[sessionId]?.cancel();
    _timeoutTimers.remove(sessionId);
  }
}
