import 'dart:async';
import 'package:flutter/services.dart';

/// Flutter <-> Android bridge for sending SMS.
///
/// Native side: MethodChannel "sms_gateway".
class SmsGateway {
  static const String _channelName = 'sms_gateway';
  static const MethodChannel _channel = MethodChannel(_channelName);

  static final _sendResultsController = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get sendResults => _sendResultsController.stream;

  static bool _listening = false;

  static void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'smsSendResult') {
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        _sendResultsController.add(args);
      }
      return null;
    });
  }

  /// Start listening for native events (e.g. inbound SMS). The native side
  /// should invoke method 'smsReceived' with an argument map containing
  /// `from`, `message`, and optional `receivedAt` ISO string.
  static void startListening(
    Future<void> Function(Map<String, dynamic>) onSms,
    {Future<void> Function(Map<String, dynamic>)? onSim}
  ) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'smsReceived') {
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        await onSms(args);
      } else if (call.method == 'simSignalChanged') {
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        if (onSim != null) await onSim(args);
      } else if (call.method == 'smsSendResult') {
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        _sendResultsController.add(args);
      }
    });
    _listening = true;
  }

  static void stopListening() {
    _channel.setMethodCallHandler(null);
    _listening = false;
  }

  /// Sends an SMS. Long messages are split into multipart SMS on Android.
  ///
  /// [to] must be an international/normalized phone number string.
  /// [message] is the full message text.
  /// [simSlot] is Android SIM index: 0 for SIM1, 1 for SIM2.
  ///
  /// Throws a [PlatformException] on failure.
  static Future<void> sendSms({
    required String to,
    required String message,
    required int simSlot,
  }) async {
    _ensureListening();
    await _channel.invokeMethod<void>('sendSms', <String, dynamic>{
      'to': to,
      'message': message,
      'simSlot': simSlot,
    });
  }

  static Future<List<dynamic>?> getPendingNativeReplies() async {
    try {
      final res = await _channel.invokeMethod<List>('nativeGetPendingReplies');
      return res;
    } catch (e) {
      return null;
    }
  }

  static Future<void> deleteNativeReply(int id) async {
    try {
      await _channel.invokeMethod('nativeDeleteReply', {'id': id});
    } catch (e) {
      // ignore
    }
  }

}

