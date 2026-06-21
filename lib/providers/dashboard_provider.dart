import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/database.dart';
import '../models/campaign.dart';
import '../models/sending_session.dart';
import '../repositories/campaign_repository.dart';
import '../repositories/sending_session_repository.dart';
import '../services/sms_service.dart';

class DashboardProvider extends ChangeNotifier {
  final _campaignRepo = CampaignRepository();
  final _sessionRepo = SendingSessionRepository();

  StreamSubscription<Map<String, dynamic>>? _sendSub;

  List<Campaign> _campaigns = [];
  List<SendingSession> _activeSessions = [];
  int _totalSent = 0;
  int _totalReplied = 0;

  /// Actual dispatched count (all outgoing messages) keyed by session ID.
  Map<int, int> _dispatchedCounts = {};

  List<Campaign> get campaigns => _campaigns;
  List<SendingSession> get activeSessions => _activeSessions;
  int get totalSent => _totalSent;
  int get totalReplied => _totalReplied;
  int get totalCampaigns => _campaigns.length;
  Map<int, int> get dispatchedCounts => _dispatchedCounts;

  bool _loading = false;
  bool get loading => _loading;

  DashboardProvider() {
    _sendSub = SmsService.instance.sendEvents.listen((evt) {
      if (evt['completed'] == true) {
        load();
      }
    });
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    _campaigns = await _campaignRepo.getAll();
    _activeSessions = await _sessionRepo.getActive();
    _activeSessions = _activeSessions.where((s) => !(s.paused)).toList();
    _totalSent = _campaigns.fold(0, (sum, c) => sum + c.sentCount);

    // Batch query dispatched counts per session (single query instead of N)
    try {
      final db = await AppDatabase.instance.database;
      final sessionIds = _activeSessions
          .where((s) => s.id != null)
          .map((s) => s.id!)
          .toList();
      if (sessionIds.isNotEmpty) {
        final placeholders = sessionIds.map((_) => '?').join(',');
        final rows = await db.rawQuery('''
          SELECT session_id, COUNT(*) as cnt
          FROM conversation_messages
          WHERE session_id IN ($placeholders) AND direction = 'out'
          GROUP BY session_id
        ''', sessionIds);
        _dispatchedCounts = {
          for (final row in rows)
            (row['session_id'] as int): row['cnt'] as int? ?? 0,
        };
      } else {
        _dispatchedCounts = {};
      }
    } catch (_) {}

    _loading = false;
    notifyListeners();
  }

  Future<void> stopSession(int sessionId) async {
    await _sessionRepo.stop(sessionId);
    await load();
  }

  @override
  void dispose() {
    _sendSub?.cancel();
    super.dispose();
  }
}