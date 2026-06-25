import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/sms_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap — could navigate to conversation
      },
    );

    // Create notification channel
    const channel = AndroidNotificationChannel(
      'sms_incoming',
      'Incoming SMS',
      description: 'Notifications for incoming SMS messages',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Listen for incoming SMS and show notification
    _sub = SmsService.instance.incomingEvents.listen((event) {
      final phone = event['phone'] as String? ?? '';
      final message = event['message'] as String? ?? '';
      showIncomingSms(phone, message);
    });
  }

  Future<void> showIncomingSms(String phone, String message) async {
    if (!_initialized) return;

    final androidDetails = AndroidNotificationDetails(
      'sms_incoming',
      'Incoming SMS',
      channelDescription: 'Notifications for incoming SMS messages',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      styleInformation: BigTextStyleInformation(message),
      fullScreenIntent: true,
      category: AndroidNotificationCategory.message,
      groupKey: 'sms_incoming_group',
    );
    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      phone.hashCode,
      phone,
      message,
      details,
    );
  }

  void dispose() {
    _sub?.cancel();
  }
}
