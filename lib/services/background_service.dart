import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class _SessionInfo {
  final String campaignName;
  final String simSlot;
  final int sent;
  final int total;
  final String status; // 'Sending', 'Paused', 'Completed', 'Stopped'
  _SessionInfo({
    required this.campaignName,
    required this.simSlot,
    required this.sent,
    required this.total,
    required this.status,
  });
}

class BulkSendingBackgroundService {
  static final BulkSendingBackgroundService _instance = BulkSendingBackgroundService._();
  static BulkSendingBackgroundService get instance => _instance;
  BulkSendingBackgroundService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  static const _channelId = 'smsgo_bulk_sending';
  static const _notificationId = 888;
  bool _initialized = false;

  /// Active sessions keyed by sessionId
  final Map<int, _SessionInfo> _sessions = {};

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (Platform.isAndroid) {
      await _createNotificationChannel();
    }

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'SMSGo',
        initialNotificationContent: 'Bulk sending active',
        foregroundServiceNotificationId: _notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
      ),
    );
  }

  Future<void> _createNotificationChannel() async {
    final plugin = FlutterLocalNotificationsPlugin();
    const channel = AndroidNotificationChannel(
      _channelId,
      'Bulk Sending',
      description: 'Shows bulk sending progress',
      importance: Importance.low,
    );
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Add a session to the notification tracker and start the service if needed
  Future<void> addSession({
    required int sessionId,
    required String campaignName,
    required String simSlot,
    required int sent,
    required int total,
  }) async {
    if (!_initialized) await init();
    _sessions[sessionId] = _SessionInfo(
      campaignName: campaignName,
      simSlot: simSlot,
      sent: sent,
      total: total,
      status: 'Sending',
    );
    _notify();
    await _ensureRunning();
  }

  /// Update a session's progress
  void updateSession({
    required int sessionId,
    required int sent,
    required int total,
    String? status,
  }) {
    final existing = _sessions[sessionId];
    if (existing == null) return;
    _sessions[sessionId] = _SessionInfo(
      campaignName: existing.campaignName,
      simSlot: existing.simSlot,
      sent: sent,
      total: total,
      status: status ?? existing.status,
    );
    _notify();
  }

  /// Remove a session from the tracker (on complete/stop). Stops service if none left.
  Future<void> removeSession(int sessionId) async {
    _sessions.remove(sessionId);
    if (_sessions.isEmpty) {
      await stopService();
    } else {
      _notify();
    }
  }

  void _notify() {
    if (!_initialized) return;
    final data = _sessions.map((id, s) => MapEntry(id.toString(), {
      'sessionId': id,
      'campaignName': s.campaignName,
      'simSlot': s.simSlot,
      'sent': s.sent,
      'total': s.total,
      'status': s.status,
    }));
    _service.invoke('updateNotification', {
      'sessions': data,
    });
  }

  Future<void> _ensureRunning() async {
    final isRunning = await _service.isRunning();
    if (!isRunning) {
      await _service.startService();
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> stopService() async {
    if (!_initialized) return;
    _sessions.clear();
    final isRunning = await _service.isRunning();
    if (isRunning) {
      _service.invoke('stopService');
    }
  }

  Future<bool> isRunning() async {
    if (!_initialized) return false;
    return _service.isRunning();
  }
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  service.on('updateNotification').listen((event) {
    if (event == null) return;
    final sessionsMap = event['sessions'] as Map<String, dynamic>?;
    if (sessionsMap == null || sessionsMap.isEmpty) return;

    final buffer = StringBuffer();
    for (final entry in sessionsMap.entries) {
      final s = entry.value as Map<String, dynamic>;
      final campaignName = s['campaignName'] as String? ?? 'Campaign';
      final simSlot = s['simSlot'] as String? ?? 'SIM';
      final sent = s['sent'] as int? ?? 0;
      final total = s['total'] as int? ?? 0;
      final status = s['status'] as String? ?? 'Sending';
      buffer.writeln('$campaignName ($simSlot): $sent/$total [$status]');
    }

    final title = sessionsMap.length == 1
        ? 'SMSGo Bulk Sending'
        : 'SMSGo Bulk Sending (${sessionsMap.length} sessions)';

    final content = buffer.toString().trimRight();

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: title,
        content: content,
      );
    }
  });

  service.on('onRebind').listen((_) {});
  service.on('onUnbind').listen((_) {});
  service.on('onDestroy').listen((_) {});
}
