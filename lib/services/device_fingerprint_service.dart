import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Generates a deterministic device fingerprint from stable hardware identifiers.
/// The fingerprint survives app reinstalls and data clears.
class DeviceFingerprintService {
  DeviceFingerprintService._();
  static final instance = DeviceFingerprintService._();

  final _deviceInfo = DeviceInfoPlugin();

  String? _fingerprint;

  String get fingerprint {
    if (_fingerprint == null) {
      throw StateError('Device fingerprint not initialized. Call init() first.');
    }
    return _fingerprint!;
  }

  /// Initialize: collect device identifiers and build fingerprint.
  Future<void> init() async {
    final parts = <String>[];
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = await _deviceInfo.androidInfo;
      parts.addAll([
        android.id,
        android.model,
        android.manufacturer,
      ]);
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = await _deviceInfo.iosInfo;
      parts.addAll([
        ios.identifierForVendor ?? '',
        ios.model,
        ios.name,
      ]);
    }

    final input = utf8.encode(parts.join('||'));
    _fingerprint = sha256.convert(input).toString();

    debugPrint('[DeviceFingerprint] fingerprint=$_fingerprint');
  }
}
