import 'package:flutter/services.dart';

/// Flutter <-> Android bridge for importing native SMS history.
///
/// Native method channel: "sms_gateway"
/// Method: "nativeImportSmsHistory"
///
/// Returns a List of row maps:
/// {
///   "nativeId": int,
///   "address": String,
///   "body": String,
///   "date": int epochMillis,
///   "type": String "inbox" | "sent"
/// }
class SmsImportGateway {
  static const _channelName = 'sms_gateway';
  static const _channel = MethodChannel(_channelName);

  static Future<List<Map<String, dynamic>>> importSmsHistory({
    required List<String> types,
    int? sinceEpochMillis,
  }) async {
    final result = await _channel.invokeMethod<List<dynamic>>('nativeImportSmsHistory', {
      'types': types,
      if (sinceEpochMillis != null) 'since': sinceEpochMillis.toString(),
    });

    if (result == null) return const [];

    return result
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  static Future<bool> isDefaultSmsApp() async {
    try {
      final res = await _channel.invokeMethod<bool>('isDefaultSmsApp');
      return res == true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> requestDefaultSmsApp() async {
    return requestDefaultSmsAppForPackage(null);
  }

  static Future<bool> requestDefaultSmsAppForPackage(String? packageName) async {
    try {
      final res = await _channel.invokeMethod<bool>('requestDefaultSmsApp', {
        if (packageName != null) 'package': packageName,
      });
      return res == true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, String>>> listSmsApps() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('listSmsApps');
      if (res == null) return [];
      return res.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return {
          'package': m['package'] as String? ?? '',
          'label': m['label'] as String? ?? m['package'] as String? ?? '',
        };
      }).toList(growable: false);
    } catch (e) {
      return [];
    }
  }
}

