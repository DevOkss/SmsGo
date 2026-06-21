import 'package:flutter/services.dart';

/// Android bridge for reading SIM/carrier/signal information.
///
/// Native side: MethodChannel "sms_gateway" with method "getDeviceSimStatus".
class DeviceSimGateway {
  static const _channel = MethodChannel('sms_gateway');

  /// Returns a list of SIM info objects.
  ///
  /// Each element is expected to match:
  /// {
  ///   "slotIndex": int,
  ///   "subscriptionId": int,
  ///   "carrier": String?,
  ///   "phoneNumber": String?,
  ///   "signal": String?,
  ///   "signalDbm": int?,
  ///   "signalAsu": int?
  /// }

  ///
  /// Note: phoneNumber may be null/empty depending on device/permissions.
  static Future<List<Map<String, dynamic>>> getDeviceSimStatus() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getDeviceSimStatus');
      print(result); // Debug log to verify native response structure
      if (result == null) return const [];

      return result
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(growable: false);
    } catch (e) {
      // Return empty list on MissingPluginException / platform errors to avoid
      // crashing the dashboard; caller will show 'No SIM info'.
      print('DeviceSimGateway.getDeviceSimStatus failed: $e');
      return const [];
    }
  }
}

