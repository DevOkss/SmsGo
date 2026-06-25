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
import '../services/license_service.dart';
import '../services/device_sim_gateway.dart';

class ActiveSend {
  final int sessionId;
  final int campaignId;
  final String campaignName;
  final String simSlot;
  final String targetNetwork;
  final String? monitorNumber;
  final String selectedGroups;
  final int rangeStart;
  final int rangeEnd;

  int sent;
  int failed;
  int total;
  int dispatched;
  bool running;
  bool completed;
  bool stopped;
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
    this.stopped = false,
    this.resting = false,
    this.monitorNumber,
    this.selectedGroups = '',
    this.rangeStart = 1,
    this.rangeEnd = 0,
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
  Timer? _debounceTimer;

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

  /// Returns set of SIM slots that are physically present and active on the device.
  Future<Set<String>> getAvailableSimSlots() async {
    try {
      final sims = await DeviceSimGateway.getDeviceSimStatus();
      final available = <String>{};
      for (final sim in sims) {
        final slotIndex = sim['slotIndex'];
        if (slotIndex is int) {
          available.add('SIM ${slotIndex + 1}');
        } else if (slotIndex is String) {
          final idx = int.tryParse(slotIndex);
          if (idx != null) available.add('SIM ${idx + 1}');
        }
      }
      return available;
    } catch (_) {
      // Fallback: assume both SIMs are available if detection fails
      return {'SIM 1', 'SIM 2'};
    }
  }

  Future<void> loadActiveSessions() async {
    try {
      final sessions = await _sessionRepo.getActive();
      final db = await AppDatabase.instance.database;
      final convRepo = ConversationRepository(db);

      // Batch fetch campaign names (single query instead of N)
      final Map<int, String> campaignNames = {};
      final campaignIds = sessions.map((s) => s.campaignId).toSet().toList();
      if (campaignIds.isNotEmpty) {
        final placeholders = campaignIds.map((_) => '?').join(',');
        final campRows = await db.query('campaigns',
          columns: ['id', 'name'],
          where: 'id IN ($placeholders)',
          whereArgs: campaignIds,
        );
        for (final row in campRows) {
          campaignNames[row['id'] as int] = row['name'] as String? ?? '';
        }
      }

      // Batch fetch dispatched counts (single query instead of N)
      final Map<int, int> dispatchedCounts = {};
      final sessionIds = sessions.where((s) => s.id != null).map((s) => s.id!).toList();
      if (sessionIds.isNotEmpty) {
        final placeholders = sessionIds.map((_) => '?').join(',');
        final countRows = await db.rawQuery('''
          SELECT session_id, COUNT(*) as cnt
          FROM conversation_messages
          WHERE session_id IN ($placeholders) AND direction = 'out'
          GROUP BY session_id
        ''', sessionIds);
        for (final row in countRows) {
          dispatchedCounts[row['session_id'] as int] = row['cnt'] as int? ?? 0;
        }
      }

      // Batch fetch unread counts (single query instead of N)
      final Map<int, int> unreadCounts = {};
      if (sessionIds.isNotEmpty) {
        final placeholders = sessionIds.map((_) => '?').join(',');
        final unreadRows = await db.rawQuery('''
          SELECT session_id, COUNT(*) as cnt
          FROM conversations
          WHERE session_id IN ($placeholders) AND unread = 1
          GROUP BY session_id
        ''', sessionIds);
        for (final row in unreadRows) {
          unreadCounts[row['session_id'] as int] = row['cnt'] as int? ?? 0;
        }
      }

      // Query imported unread count
      _importedUnreadCount = await convRepo.getUnreadCountForImported();

      // Detect orphaned sessions (running in DB but no active timer)
      final orphanedSessions = <SendingSession>[];
      for (final s in sessions) {
        if (s.id != null && s.running && !s.paused && !_sms.isRunning(s.id!)) {
          orphanedSessions.add(s);
        }
      }

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
          rangeStart: s.rangeStart,
          rangeEnd: s.rangeEnd > 0 ? s.rangeEnd : s.totalTargets,
          sent: prev != null && prev.sent > s.sentCount ? prev.sent : s.sentCount,
          failed: prev != null && prev.failed > s.failedCount ? prev.failed : s.failedCount,
          dispatched: prev != null && prev.dispatched > dbDispatched ? prev.dispatched : dbDispatched,
          total: s.totalTargets,
          running: s.running && !s.paused,
          completed: !s.running && !s.stopped,
          stopped: s.stopped,
          resting: prev?.resting ?? false,
          countdownSeconds: prev?.countdownSeconds ?? 0,
          isCountingDown: prev?.isCountingDown ?? false,
          lastMessage: prev?.lastMessage ?? '',
          unreadCount: unreadCounts[s.id!] ?? 0,
        );
      }).toList();

      // Store orphaned sessions for potential resume
      _orphanedSessions = orphanedSessions;
    } catch (_) {}
    notifyListeners();
  }

  List<SendingSession> _orphanedSessions = [];
  List<SendingSession> get orphanedSessions => _orphanedSessions;

  /// Resume all orphaned sessions (after app restart)
  Future<void> resumeOrphanedSessions() async {
    for (final session in _orphanedSessions) {
      if (session.id != null) {
        try {
          await _sms.resumeSession(session.id!);
        } catch (_) {}
      }
    }
    _orphanedSessions.clear();
    await loadActiveSessions();
  }

  /// Stop all orphaned sessions (don't resume)
  Future<void> stopOrphanedSessions() async {
    for (final session in _orphanedSessions) {
      if (session.id != null) {
        try {
          await _sms.stopSession(session.id!);
        } catch (_) {}
      }
    }
    _orphanedSessions.clear();
    await loadActiveSessions();
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
    String breakLinkMode = 'none',
  }) async {
    // License guard: check before doing any work
    final licenseStatus = await LicenseService.instance.validate();
    if (licenseStatus != LicenseStatus.active && licenseStatus != LicenseStatus.cached) {
      throw Exception('A valid license is required to send SMS. Please activate your license in Settings.');
    }

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
      rangeStart: rangeStart ?? 1,
      rangeEnd: rangeEnd ?? targets.length,
      createdAt: DateTime.now().toIso8601String(),
    );

    final sessionIdHolder = [0]; // mutable holder so onProgress can access it
    final effectiveRangeEnd = rangeEnd ?? targets.length;
    final effectiveRangeStart = rangeStart ?? 1;
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
      rangeStart: effectiveRangeStart,
      rangeEnd: effectiveRangeEnd,
    );
    _active.add(newSession);
    notifyListeners();

    final sessionId = await _sms.startSession(
      session: session,
      messages: messages,
      targets: targets,
      breakLinkMode: breakLinkMode,
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
            rangeStart: effectiveRangeStart,
            rangeEnd: effectiveRangeEnd,
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

  Future<void> resumeSending(int sessionId, {String breakLinkMode = 'Globe'}) async {
    await _sms.resumeSession(sessionId, breakLinkMode: breakLinkMode);
    // Reload from DB to get a fresh object (mutating in place won't trigger Consumer rebuild)
    await loadActiveSessions();
  }

  Future<void> stopSending(int sessionId) async {
    await _sms.stopSession(sessionId);
    await loadActiveSessions();
  }

  Future<void> removeSession(int sessionId) async {
    // Permanently delete the session from the database.
    // Conversations stay linked to the campaign.
    await _sessionRepo.delete(sessionId);
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
          if (active.dispatched > 0) active.dispatched--;
        } else if (evt['success'] == false) {
          active.failed++;
          if (active.dispatched > 0) active.dispatched--;
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
      // Debounce: refresh unread counts when a new incoming reply arrives
      _debouncedLoadSessions();
    });
  }

  void _listenForConvChanges() {
    _convChangeSub = ConversationRepository.onChange.listen((_) {
      // Debounce: refresh badge counts when read/unread status or ownership changes
      _debouncedLoadSessions();
    });
  }

  void _debouncedLoadSessions() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      loadActiveSessions();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _sendSub?.cancel();
    _incomingSub?.cancel();
    _convChangeSub?.cancel();
    _countdownTicker?.cancel();
    super.dispose();
  }
}
