import 'package:flutter/foundation.dart';
import 'dart:async';
import '../database/database.dart';
import '../models/conversation.dart';
import '../models/conversation_message.dart';
import '../repositories/conversation_repository.dart';
import '../services/sms_service.dart';
import '../services/sms_gateway.dart';
import 'messaging_provider.dart';

/// Per-session progress state for the campaign
class SessionProgress {
  final int sessionId;
  String simSlot;
  String? monitorNumber;
  int sent;
  int failed;
  int total;
  int dispatched;
  bool running;
  bool completed;
  bool paused;
  bool resting;
  int restSeconds;
  int restRemaining;
  int nextSendCountdown;

  SessionProgress({
    required this.sessionId,
    this.simSlot = 'SIM 1',
    this.monitorNumber,
    this.sent = 0,
    this.failed = 0,
    this.total = 0,
    this.dispatched = 0,
    this.running = true,
    this.completed = false,
    this.paused = false,
    this.resting = false,
    this.restSeconds = 0,
    this.restRemaining = 0,
    this.nextSendCountdown = 0,
  });

  bool get isDone => completed || !running;
}

class ActiveSendProvider extends ChangeNotifier {
  final int campaignId;
  final MessagingProvider? _messaging;
  final _dbFuture = AppDatabase.instance.database;
  ConversationRepository? _repo;

  List<Conversation> conversations = [];
  Map<int, List<ConversationMessage>> messages = {};

  /// conversationId -> latest outgoing message status
  Map<int, String?> conversationSendStatus = {};

  /// phone -> latest status (for placeholders before DB lookup completes)
  final Map<String, String?> _pendingStatuses = {};

  /// All sessions for this campaign (multiple bulk send jobs)
  List<SessionProgress> sessions = [];

  /// Rest countdown timers per session
  final Map<int, Timer> _restTimers = {};

  /// Next send countdown timers per session
  final Map<int, Timer> _nextSendTimers = {};

  bool loading = false;

  late final Future<void> _ready;
  StreamSubscription<Map<String, dynamic>>? _sendSub;
  StreamSubscription<Map<String, dynamic>>? _incomingSub;
  StreamSubscription<void>? _convChangeSub;
  Timer? _messagingDebounce;

  ActiveSendProvider(this.campaignId, {MessagingProvider? messaging}) : _messaging = messaging {
    loading = true;
    _messaging?.addListener(_onMessagingChanged);
    _ready = _init();
  }

  Future<void> _init() async {
    try {
      _sendSub = SmsService.instance.sendEvents.listen((evt) {
        _handleSendEvent(evt);
      });
    } catch (_) {}

    try {
      _incomingSub = SmsService.instance.incomingEvents.listen((_) {
        reloadConversations();
      });
    } catch (_) {}

    try {
      _convChangeSub = ConversationRepository.onChange.listen((_) {
        reloadConversations();
      });
    } catch (_) {}

    try {
      final db = await _dbFuture;
      _repo = ConversationRepository(db);

      // Load ALL sessions for this campaign
      final sessRows = await db.query(
        'sending_sessions',
        where: 'campaign_id = ?',
        whereArgs: [campaignId],
        orderBy: 'id DESC',
      );

      // Batch fetch counts for all sessions (single query instead of N)
      final sessionIds = sessRows.map((r) => r['id'] as int).toList();
      final Map<int, Map<String, int>> sessionCounts = {};
      if (sessionIds.isNotEmpty) {
        final placeholders = sessionIds.map((_) => '?').join(',');
        final countRows = await db.rawQuery('''
          SELECT session_id, status, COUNT(*) as cnt
          FROM conversation_messages
          WHERE session_id IN ($placeholders) AND direction = 'out'
          GROUP BY session_id, status
        ''', sessionIds);
        for (final row in countRows) {
          final sessId = row['session_id'] as int;
          final status = row['status'] as String?;
          final cnt = row['cnt'] as int? ?? 0;
          sessionCounts.putIfAbsent(sessId, () => {'sent': 0, 'failed': 0, 'dispatched': 0});
          sessionCounts[sessId]!['dispatched'] = sessionCounts[sessId]!['dispatched']! + cnt;
          if (status == 'sent') sessionCounts[sessId]!['sent'] = cnt;
          if (status == 'failed') sessionCounts[sessId]!['failed'] = cnt;
        }
      }

      sessions = [];
      for (final row in sessRows) {
        final sessId = row['id'] as int;
        final running = row['running'] as int? ?? 1;
        final isPaused = row['paused'] as int? ?? 0;
        final counts = sessionCounts[sessId] ?? {'sent': 0, 'failed': 0, 'dispatched': 0};

        sessions.add(SessionProgress(
          sessionId: sessId,
          simSlot: row['sim_slot'] as String? ?? 'SIM 1',
          monitorNumber: row['monitor_number'] as String?,
          sent: counts['sent']!,
          failed: counts['failed']!,
          dispatched: counts['dispatched']!,
          total: row['total_targets'] as int? ?? 0,
          running: running == 1,
          completed: running == 0,
          paused: isPaused == 1 && running == 1,
        ));
      }

      // Load conversations by campaign_id
      conversations = await _repo!.getConversationsForCampaign(campaignId);
      final ids = conversations.map((c) => c.id!).toList();
      conversationSendStatus = await _repo!.getLatestOutgoingStatusesForConversations(ids);
    } catch (e) {
      print('WARNING: ActiveSendProvider._init failed: $e');
    }

    loading = false;
    notifyListeners();
  }

  void _handleSendEvent(Map<String, dynamic> evt) {
    try {
      final sessId = evt['sessionId'] as int?;
      if (sessId == null) return;

      // Check if this event belongs to any session in our campaign
      final sessIdx = sessions.indexWhere((s) => s.sessionId == sessId);
      if (sessIdx < 0) return;

      final sess = sessions[sessIdx];

      // Handle completion
      if (evt['completed'] == true) {
        sess.completed = true;
        sess.running = false;
        sess.paused = false;
        sess.resting = false;
        sess.restRemaining = 0;
        sess.nextSendCountdown = 0;
        _restTimers[sessId]?.cancel();
        _nextSendTimers[sessId]?.cancel();
        _reloadSessionCounts(sessId);
        notifyListeners();
        return;
      }

      // Handle countdown (interval + rest combined)
      if (evt['countdown'] == true) {
        final totalWait = evt['totalWait'] as int? ?? 0;
        final restSecs = evt['restSeconds'] as int? ?? 0;
        sess.resting = restSecs > 0;
        sess.restSeconds = restSecs;
        sess.restRemaining = restSecs > 0 ? restSecs : 0;
        sess.nextSendCountdown = totalWait;
        if (restSecs > 0) {
          _startRestCountdown(sess);
        }
        _startNextSendCountdown(sess);
        notifyListeners();
        return;
      }

      // Handle rest start
      if (evt['resting'] == true) {
        sess.resting = true;
        sess.restSeconds = evt['restSeconds'] as int? ?? 30;
        sess.restRemaining = sess.restSeconds;
        _startRestCountdown(sess);
        notifyListeners();
        return;
      }

      // Handle rest end
      if (evt['resting'] == false) {
        sess.resting = false;
        _restTimers[sessId]?.cancel();
        notifyListeners();
        return;
      }

      // Handle send events
      final phone = (evt['phone'] ?? '') as String;
      final status = evt['status'] as String?;

      var idx = conversations.indexWhere(
        (c) => c.phoneNumber.trim() == phone.trim(),
      );

      if (idx < 0) {
        final phoneKey = phone.trim();
        final placeholder = Conversation(
          phoneNumber: phone,
          sessionId: sessId,
          campaignId: campaignId,
          createdAt: DateTime.now().toIso8601String(),
          lastMessage: null,
        );
        conversations.insert(0, placeholder);
        _pendingStatuses[phoneKey] = status;
        _findAndReplacePlaceholder(placeholder);
        if (status == 'sending') sess.dispatched++;
        if (status == 'sent') sess.sent++;
        if (status == 'failed') sess.failed++;
        notifyListeners();
        return;
      }

      final conv = conversations[idx];
      final phoneKey = phone.trim();
      if (conv.id != null) {
        conversationSendStatus[conv.id!] = status;
      } else {
        _pendingStatuses[phoneKey] = status;
      }
      if (status == 'sending') sess.dispatched++;
      if (status == 'sent') sess.sent++;
      if (status == 'failed') sess.failed++;
      reloadConversations();
      return;
    } catch (_) {}
  }

  Future<void> _findAndReplacePlaceholder(Conversation placeholder) async {
    try {
      final db = await _dbFuture;
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
        WHERE c.campaign_id = ? AND c.phone_number = ?
        LIMIT 1
      ''', [campaignId, placeholder.phoneNumber]);
      if (rows.isNotEmpty) {
        final real = Conversation.fromMap(rows.first);
        final idx = conversations.indexOf(placeholder);
        if (idx >= 0) {
          conversations[idx] = real;
        } else {
          final exists = conversations.any((c) => c.id == real.id);
          if (!exists) conversations.insert(0, real);
        }
        final phoneKey = placeholder.phoneNumber.trim();
        final pendingStatus = _pendingStatuses.remove(phoneKey);
        if (real.id != null) {
          conversationSendStatus[real.id!] = pendingStatus;
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _reloadSessionCounts(int sessionId) async {
    try {
      final db = await _dbFuture;
      final sessIdx = sessions.indexWhere((s) => s.sessionId == sessionId);
      if (sessIdx < 0) return;
      int sentCount = 0;
      int failedCount = 0;
      int dispatchedCount = 0;
      final rows = await db.rawQuery('''
        SELECT cm.status, COUNT(*) as cnt
        FROM conversation_messages cm
        WHERE cm.session_id = ? AND cm.direction = 'out'
        GROUP BY cm.status
      ''', [sessionId]);
      for (final row in rows) {
        final status = row['status'] as String?;
        final cnt = row['cnt'] as int? ?? 0;
        dispatchedCount += cnt;
        if (status == 'sent') sentCount = cnt;
        if (status == 'failed') failedCount = cnt;
      }
      sessions[sessIdx].sent = sentCount;
      sessions[sessIdx].failed = failedCount;
      sessions[sessIdx].dispatched = dispatchedCount;
    } catch (_) {}
  }

  void _startRestCountdown(SessionProgress sess) {
    _restTimers[sess.sessionId]?.cancel();
    _restTimers[sess.sessionId] = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (sess.restRemaining > 0) {
        sess.restRemaining--;
        notifyListeners();
      } else {
        timer.cancel();
      }
    });
  }

  void _startNextSendCountdown(SessionProgress sess) {
    _nextSendTimers[sess.sessionId]?.cancel();
    _nextSendTimers[sess.sessionId] = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (sess.nextSendCountdown > 0) {
        sess.nextSendCountdown--;
        notifyListeners();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> reloadConversations() async {
    try {
      if (_repo == null) return;
      final newConversations = await _repo!.getConversationsForCampaign(campaignId);
      conversations = newConversations;
      final ids = conversations.map((c) => c.id!).toList();
      final dbStatuses = await _repo!.getLatestOutgoingStatusesForConversations(ids);
      for (final id in ids) {
        final inMemory = conversationSendStatus[id];
        if (inMemory == 'sending') continue;
        conversationSendStatus[id] = dbStatuses[id];
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Marks all conversations for a session as read and refreshes counts.
  Future<void> markSessionRead(int sessionId) async {
    try {
      if (_repo == null) return;
      await _repo!.markAllReadForSession(sessionId);
      await reloadConversations();
      // Refresh unread counts in MessagingProvider
      _messaging?.loadActiveSessions();
    } catch (_) {}
  }

  @override
  void dispose() {
    _messaging?.removeListener(_onMessagingChanged);
    _messagingDebounce?.cancel();
    _sendSub?.cancel();
    _incomingSub?.cancel();
    _convChangeSub?.cancel();
    for (final t in _nextSendTimers.values) {
      t.cancel();
    }
    _nextSendTimers.clear();
    super.dispose();
  }

  void _onMessagingChanged() {
    // Debounce: avoid cascading rebuilds from MessagingProvider
    _messagingDebounce?.cancel();
    _messagingDebounce = Timer(const Duration(milliseconds: 300), () {
      // Sync session states from MessagingProvider
      final m = _messaging;
      if (m == null) return;
      for (final sess in sessions) {
        final match = m.active.where((a) => a.sessionId == sess.sessionId).firstOrNull;
        if (match == null) {
          if (!sess.completed) {
            sess.completed = true;
            sess.running = false;
            sess.paused = false;
          }
        } else {
          sess.running = match.running;
          sess.paused = !match.running;
        }
      }
      notifyListeners();
    });
  }

  Future<void> loadConversations({bool? replied}) async {
    await _ready;
    loading = true;
    notifyListeners();
    conversations = await _repo!.getConversationsForCampaign(campaignId, replied: replied);
    final ids = conversations.map((c) => c.id!).toList();
    conversationSendStatus = await _repo!.getLatestOutgoingStatusesForConversations(ids);
    loading = false;
    notifyListeners();
  }

  Future<void> loadMessages(int conversationId) async {
    final msgs = await _repo!.getMessagesForConversation(conversationId);
    messages[conversationId] = msgs;
    notifyListeners();
  }

  Future<void> sendReply(int conversationId, String text) async {
    final conv = conversations.firstWhere((c) => c.id == conversationId);

    // Find the session to use for SIM slot
    String simSlot = 'SIM 1';
    // Use the first running session, or the most recent one
    final activeSession = sessions.firstWhere(
      (s) => s.running,
      orElse: () => sessions.isNotEmpty ? sessions.first : SessionProgress(sessionId: 0),
    );
    simSlot = activeSession.simSlot;
    final simIndex = simSlot == 'SIM 2' ? 1 : 0;

    final sendingMessageId = await _repo!.addMessage(
      conversationId,
      'out',
      text,
      status: 'sending',
      sessionId: activeSession.sessionId,
    );

    // Update in-memory conversation so tile shows new message immediately
    final idx = conversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0) {
      final old = conversations[idx];
      conversations[idx] = Conversation(
        id: old.id,
        sessionId: old.sessionId,
        campaignId: old.campaignId,
        leadId: old.leadId,
        phoneNumber: old.phoneNumber,
        lastMessage: text,
        replied: old.replied,
        unread: old.unread,
        createdAt: old.createdAt,
        lastActivity: DateTime.now().toIso8601String(),
        outgoingStatus: 'sending',
        lastDirection: 'out',
      );
    }

    conversationSendStatus[conversationId] = 'sending';
    notifyListeners();

    try {
      await SmsGateway.sendSms(to: conv.phoneNumber, message: text, simSlot: simIndex);
      await _repo!.updateMessageStatus(sendingMessageId, 'sent');
      conversationSendStatus[conversationId] = 'sent';
      SmsService.instance.emitSendEvent({
        'phone': conv.phoneNumber,
        'success': true,
        'sessionId': conv.sessionId,
        'status': 'sent',
      });
    } catch (_) {
      await _repo!.updateMessageStatus(sendingMessageId, 'failed');
      conversationSendStatus[conversationId] = 'failed';
      SmsService.instance.emitSendEvent({
        'phone': conv.phoneNumber,
        'success': false,
        'sessionId': conv.sessionId,
        'status': 'failed',
      });
      rethrow;
    }

    await _repo!.markReplied(conversationId, true);
    await loadMessages(conversationId);
  }

  Future<void> togglePause(int sessionId) async {
    final sess = sessions.firstWhere((s) => s.sessionId == sessionId);
    if (sess.paused) {
      await SmsService.instance.resumeSession(sessionId);
      sess.paused = false;
      sess.running = true;
      _messaging?.resumeSending(sessionId);
    } else {
      await SmsService.instance.pauseSession(sessionId);
      sess.paused = true;
      sess.running = false;
      _messaging?.pauseSending(sessionId);
    }
    notifyListeners();
  }

  Future<void> stopSessionById(int sessionId) async {
    await SmsService.instance.stopSession(sessionId);
    final sess = sessions.firstWhere((s) => s.sessionId == sessionId);
    sess.completed = true;
    sess.running = false;
    sess.paused = false;
    _messaging?.stopSending(sessionId);
    notifyListeners();
  }
}
