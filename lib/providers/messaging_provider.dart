import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../database/database.dart';
import '../models/campaign.dart';
import '../models/monitor_number.dart';
import '../models/note.dart';
import '../models/sending_session.dart';
import '../repositories/conversation_repository.dart';
import '../repositories/lead_repository.dart';
import '../repositories/monitor_number_repository.dart';
import '../repositories/notes_repository.dart';
import '../repositories/sending_session_repository.dart';
import '../services/sms_service.dart';

class ActiveSend {
  final int sessionId;
  final int campaignId;
  final String campaignName;
  final String simSlot;
  final String targetNetwork;
  final String? monitorNumber;
  final String selectedGroups;

  int sent;
  int failed;
  int total;
  int dispatched;
  bool running;
  bool completed;
  bool resting;
  String lastMessage;
  int unreadCount;

  // Countdown state
  int countdownSeconds;
  bool isCountingDown;

  ActiveSend({
    required this.sessionId,
    required this.campaignId,
    required this.campaignName,
    required this.simSlot,
    required this.targetNetwork,
    required this.sent,
    required this.failed,
    required this.total,
    this.dispatched = 0,
    this.running = true,
    this.completed = false,
    this.resting = false,
    this.monitorNumber,
    this.selectedGroups = '',
    this.lastMessage = '',
    this.unreadCount = 0,
    this.countdownSeconds = 0,
    this.isCountingDown = false,
  });

  double get progress => total > 0 ? dispatched / total : 0;
}

class MessagingProvider extends ChangeNotifier {
  final _sessionRepo = SendingSessionRepository();
  final _leadRepo = LeadRepository();
  final _monitorRepo = MonitorNumberRepository();
  final _notesRepo = NoteRepository();
  final _sms = SmsService.instance;

  StreamSubscription<Map<String, dynamic>>? _sendSub;
  StreamSubscription<Map<String, dynamic>>? _incomingSub;
  StreamSubscription<void>? _convChangeSub;
  Timer? _countdownTicker;

  List<ActiveSend> _active = [];
  List<ActiveSend> get active => _active;

  int _importedUnreadCount = 0;
  int get importedUnreadCount => _importedUnreadCount;

  List<MonitorNumber> _monitorNumbers = [];
  List<MonitorNumber> get monitorNumbers => _monitorNumbers;

  MessagingProvider() {
    _listenForCompletion();
    _listenForIncoming();
    _listenForConvChanges();
  }

  /// Returns set of SIM slots currently in use by active sessions.
  Set<String> getActiveSims() {
    final sims = <String>{};
    for (final a in _active) {
      if (!a.running) continue;
      if (a.simSlot == 'Both') {
        sims.add('SIM 1');
        sims.add('SIM 2');
      } else {
        sims.add(a.simSlot);
      }
    }
    return sims;
  }

  Future<void> loadActiveSessions() async {
    try {
      final sessions = await _sessionRepo.getActive();
      // Fetch campaign names via direct DB query
      final db = await AppDatabase.instance.database;
      final convRepo = ConversationRepository(db);
      final Map<int, String> campaignNames = {};
      for (final s in sessions) {
        if (!campaignNames.containsKey(s.campaignId)) {
          final rows = await db.query('campaigns',
            columns: ['name'],
            where: 'id = ?',
            whereArgs: [s.campaignId],
            limit: 1,
          );
          campaignNames[s.campaignId] = rows.isNotEmpty ? (rows.first['name'] as String? ?? 'Campaign #${s.campaignId}') : 'Campaign #${s.campaignId}';
        }
      }

      // Query actual dispatched counts from conversation_messages for each session
      final Map<int, int> dispatchedCounts = {};
      // Query unread counts per session
      final Map<int, int> unreadCounts = {};
      for (final s in sessions) {
        if (s.id == null) continue;
        final countRows = await db.rawQuery('''
          SELECT COUNT(*) as cnt
          FROM conversation_messages cm
          WHERE cm.session_id = ? AND cm.direction = 'out'
        ''', [s.id]);
        dispatchedCounts[s.id!] = countRows.isNotEmpty ? (countRows.first['cnt'] as int? ?? 0) : 0;
        unreadCounts[s.id!] = await convRepo.getUnreadCountForSession(s.id!);
      }

      // Query imported unread count
      _importedUnreadCount = await convRepo.getUnreadCountForImported();

      _active = sessions.where((s) => s.id != null).map((s) {
        // Preserve countdown state and higher counts from existing objects if still active
        final existing = _active.where((a) => a.sessionId == s.id);
        final prev = existing.isNotEmpty ? existing.first : null;
        final dbDispatched = dispatchedCounts[s.id!] ?? 0;
        return ActiveSend(
          sessionId: s.id!,
          campaignId: s.campaignId,
          campaignName: campaignNames[s.campaignId] ?? 'Campaign #${s.campaignId}',
          simSlot: s.simSlot,
          targetNetwork: s.targetNetwork,
          monitorNumber: s.monitorNumber,
          selectedGroups: s.selectedGroups,
          sent: prev != null && prev.sent > s.sentCount ? prev.sent : s.sentCount,
          failed: prev != null && prev.failed > s.failedCount ? prev.failed : s.failedCount,
          dispatched: prev != null && prev.dispatched > dbDispatched ? prev.dispatched : dbDispatched,
          total: s.totalTargets,
          running: s.running && !s.paused,
          completed: !s.running,
          resting: prev?.resting ?? false,
          countdownSeconds: prev?.countdownSeconds ?? 0,
          isCountingDown: prev?.isCountingDown ?? false,
          lastMessage: prev?.lastMessage ?? '',
          unreadCount: unreadCounts[s.id!] ?? 0,
        );
      }).toList();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> loadMonitorNumbers() async {
    _monitorNumbers = await _monitorRepo.getAll();
    notifyListeners();
  }

  Future<int> startSending({
    required Campaign campaign,
    required String simSlot,
    required String targetNetwork,
    required String messageMode,
    required List<String> selectedGroups,
    required int sendIntervalMin,
    required int sendIntervalMax,
    required bool restEnabled,
    required int restSeconds,
    required int restAfterCount,
    int progressNotifyAfter = 0,
    String? monitorNumber,
    int? rangeStart,
    int? rangeEnd,
  }) async {
    final targets = await _leadRepo.getUnsent(campaign.id!, network: targetNetwork, rangeStart: rangeStart, rangeEnd: rangeEnd);
    if (targets.isEmpty) throw Exception('No unsent leads for this selection');
    if (selectedGroups.isEmpty) throw Exception('No message groups selected');

    // Load notes from selected groups
    final allNotes = <Note>[];
    for (final group in selectedGroups) {
      final notes = await _notesRepo.getByGroup(group);
      allNotes.addAll(notes);
    }
    if (allNotes.isEmpty) throw Exception('Selected groups have no notes');

    // Prepare message list based on mode
    List<Note> messages;
    if (messageMode == 'sequential') {
      // Sequential: group notes together so each group's notes are sent in order
      messages = [];
      for (final group in selectedGroups) {
        final groupNotes = allNotes.where((n) => n.groupName == group).toList();
        messages.addAll(groupNotes);
      }
    } else {
      // Rotational: shuffle all notes randomly
      messages = List.from(allNotes)..shuffle(Random());
    }

    final session = SendingSession(
      campaignId: campaign.id!,
      simSlot: simSlot,
      targetNetwork: targetNetwork,
      messageMode: messageMode,
      sendInterval: sendIntervalMin,
      sendIntervalMin: sendIntervalMin,
      sendIntervalMax: sendIntervalMax,
      restEnabled: restEnabled,
      restSeconds: restSeconds,
      restAfterCount: restAfterCount,
      progressNotifyAfter: progressNotifyAfter,
      monitorNumber: monitorNumber,
      selectedGroups: selectedGroups.join(', '),
      createdAt: DateTime.now().toIso8601String(),
    );

    final sessionIdHolder = [0]; // mutable holder so onProgress can access it
    final newSession = ActiveSend(
      sessionId: 0, // temporary, will be updated
      campaignId: campaign.id!,
      campaignName: campaign.name,
      simSlot: simSlot,
      targetNetwork: targetNetwork,
      monitorNumber: monitorNumber,
      selectedGroups: selectedGroups.join(', '),
      sent: 0,
      failed: 0,
      total: targets.length,
    );
    _active.add(newSession);
    notifyListeners();

    final sessionId = await _sms.startSession(
      session: session,
      messages: messages,
      targets: targets,
      onSessionCreated: (id) {
        // Update the session ID on the ActiveSend object
        final idx = _active.indexOf(newSession);
        if (idx >= 0) {
          _active.removeAt(idx);
          final updated = ActiveSend(
            sessionId: id,
            campaignId: campaign.id!,
            campaignName: campaign.name,
            simSlot: simSlot,
            targetNetwork: targetNetwork,
            monitorNumber: monitorNumber,
            selectedGroups: selectedGroups.join(', '),
            sent: 0,
            failed: 0,
            total: targets.length,
          );
          _active.insert(idx, updated);
          notifyListeners();
        }
        sessionIdHolder[0] = id;
      },
      onProgress: (sent, failed, total, {String lastMessage = '', int dispatched = 0}) {
        final idx = _active.indexWhere((a) => a.sessionId == sessionIdHolder[0]);
        if (idx >= 0) {
          _active[idx].sent = sent;
          _active[idx].failed = failed;
          _active[idx].dispatched = dispatched;
          _active[idx].lastMessage = lastMessage;
          if (sent + failed >= total) _active[idx].running = false;
          notifyListeners();
        }
      },
    );

    notifyListeners();
    return sessionId;
  }

  Future<void> pauseSending(int sessionId) async {
    await _sms.pauseSession(sessionId);
    // Reload from DB to get a fresh object (mutating in place won't trigger Consumer rebuild)
    await loadActiveSessions();
  }

  Future<void> resumeSending(int sessionId) async {
    await _sms.resumeSession(sessionId);
    // Reload from DB to get a fresh object (mutating in place won't trigger Consumer rebuild)
    await loadActiveSessions();
  }

  Future<void> stopSending(int sessionId) async {
    await _sms.stopSession(sessionId);
    await loadActiveSessions();
  }

  Future<void> removeSession(int sessionId) async {
    // Hide the session from the active list without deleting it or clearing session_id.
    // Conversations stay linked to the campaign until a new incoming reply arrives
    // from a contact with no active session, at which point they move to Imported Messages.
    final db = await AppDatabase.instance.database;
    await db.update(
      'sending_sessions',
      {'ended_at': null, 'running': 0},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    await loadActiveSessions();
  }

  Future<void> saveMonitorNumber(String phone, {String? label}) async {
    await _monitorRepo.save(MonitorNumber(
      phoneNumber: phone,
      label: label,
      createdAt: DateTime.now().toIso8601String(),
    ));
    await loadMonitorNumbers();
  }

  Future<void> deleteMonitorNumber(int id) async {
    await _monitorRepo.delete(id);
    await loadMonitorNumbers();
  }

  Future<Map<String, int>> getUnsentNetworkCounts(int campaignId) =>
      _leadRepo.getUnsentNetworkCounts(campaignId);

  Future<int> getUnsentCount(int campaignId, {String? network}) =>
      _leadRepo.getUnsentCount(campaignId, network: network);

  /// Listen for send/completion/resting/countdown events from SmsService so _ActiveSendCard stays in sync
  void _listenForCompletion() {
    _sendSub = _sms.sendEvents.listen((evt) {
      final sessionId = evt['sessionId'] as int?;
      if (sessionId == null) return;

      final match = _active.where((a) => a.sessionId == sessionId);
      if (match.isEmpty) return;
      final active = match.first;

      // Handle countdown events
      if (evt['countdown'] == true) {
        final totalWait = evt['totalWait'] as int? ?? 0;
        active.countdownSeconds = totalWait;
        active.isCountingDown = true;
        active.resting = (evt['restSeconds'] as int? ?? 0) > 0;
        notifyListeners();
        _startCountdownTicker();
        return;
      }

      // Update resting state
      if (evt['resting'] != null) {
        active.resting = evt['resting'] as bool;
        if (evt['resting'] == false) {
          active.isCountingDown = false;
          active.countdownSeconds = 0;
        }
        notifyListeners();
      }

      // Update sent/failed counts for matching session
      if (evt['phone'] != null && (evt['phone'] as String).isNotEmpty) {
        final status = evt['status'] as String?;
        if (status == 'sending') {
          active.dispatched++;
        } else if (evt['success'] == true) {
          active.sent++;
        } else if (evt['success'] == false) {
          active.failed++;
        }
        active.lastMessage = evt['message'] as String? ?? active.lastMessage;
        notifyListeners();
      }

      // Reload from DB on completion
      if (evt['completed'] == true) {
        active.isCountingDown = false;
        active.countdownSeconds = 0;
        active.resting = false;
        _stopCountdownTicker();
        loadActiveSessions();
      }
    });
  }

  void _startCountdownTicker() {
    _countdownTicker?.cancel();
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      bool anyActive = false;
      for (final a in _active) {
        if (a.isCountingDown && a.countdownSeconds > 0) {
          a.countdownSeconds--;
          anyActive = true;
          if (a.countdownSeconds <= 0) {
            a.isCountingDown = false;
            a.resting = false;
          }
        }
      }
      if (anyActive) notifyListeners();
      else _countdownTicker?.cancel();
    });
  }

  void _stopCountdownTicker() {
    bool anyCountingDown = _active.any((a) => a.isCountingDown);
    if (!anyCountingDown) {
      _countdownTicker?.cancel();
      _countdownTicker = null;
    }
  }

  void _listenForIncoming() {
    _incomingSub = _sms.incomingEvents.listen((_) {
      // Refresh unread counts when a new incoming reply arrives
      loadActiveSessions();
    });
  }

  void _listenForConvChanges() {
    _convChangeSub = ConversationRepository.onChange.listen((_) {
      // Refresh badge counts when read/unread status or ownership changes
      loadActiveSessions();
    });
  }

  @override
  void dispose() {
    _sendSub?.cancel();
    _incomingSub?.cancel();
    _convChangeSub?.cancel();
    _countdownTicker?.cancel();
    super.dispose();
  }
}
