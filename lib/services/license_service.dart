import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_fingerprint_service.dart';

/// License validation status.
enum LicenseStatus {
  /// Not validated yet.
  unknown,

  /// Key is valid, device is bound, not expired.
  active,

  /// Key exists but has expired.
  expired,

  /// Key format invalid or key not found in database.
  invalid,

  /// Key has been revoked by admin.
  revoked,

  /// Device limit reached (different device tried to bind).
  deviceLimitReached,

  /// Network error, using cached status.
  cached,

  /// No key has been activated on this device.
  unlicensed,
}

/// Cached license data for offline use.
class LicenseCache {
  final String? keyCode;
  final DateTime? expiresAt;
  final LicenseStatus status;

  LicenseCache({this.keyCode, this.expiresAt, this.status = LicenseStatus.unlicensed});

  Map<String, dynamic> toJson() => {
        'keyCode': keyCode,
        'expiresAt': expiresAt?.toIso8601String(),
        'status': status.index,
      };

  factory LicenseCache.fromJson(Map<String, dynamic> json) => LicenseCache(
        keyCode: json['keyCode'] as String?,
        expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt']) : null,
        status: LicenseStatus.values[json['status'] as int? ?? 0],
      );
}

class LicenseService {
  LicenseService._();
  static final instance = LicenseService._();

  static const _cacheKey = 'license_cache_v1';

  final _client = Supabase.instance.client;

  LicenseCache? _cachedLicense;
  LicenseCache? get cachedLicense => _cachedLicense;

  /// Load cached license from SharedPreferences.
  Future<void> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);
      if (json != null) {
        _cachedLicense = LicenseCache.fromJson(jsonDecode(json));
        debugPrint('[LicenseService] loaded cache: ${_cachedLicense?.status}');
      }
    } catch (e) {
      debugPrint('[LicenseService] loadCache error: $e');
    }
  }

  /// Save license to local cache.
  Future<void> _saveCache(LicenseCache cache) async {
    _cachedLicense = cache;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(cache.toJson()));
    } catch (e) {
      debugPrint('[LicenseService] saveCache error: $e');
    }
  }

  /// Clear the license cache.
  Future<void> clearCache() async {
    _cachedLicense = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (e) {
      debugPrint('[LicenseService] clearCache error: $e');
    }
  }

  /// Validate license by calling the Supabase Edge Function.
  Future<LicenseStatus> validate() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      final cache = LicenseCache(status: LicenseStatus.unlicensed);
      await _saveCache(cache);
      return LicenseStatus.unlicensed;
    }

    final fingerprint = DeviceFingerprintService.instance.fingerprint;

    try {
      final response = await _client.functions.invoke(
        'validate-license',
        body: {
          'device_fingerprint': fingerprint,
        },
      );

      if (response.status != 200) {
        debugPrint('[LicenseService] validate failed: ${response.status}');
        // Fall back to cache
        if (_cachedLicense != null && _cachedLicense!.expiresAt != null) {
          if (_cachedLicense!.expiresAt!.isAfter(DateTime.now())) {
            await _saveCache(LicenseCache(
              keyCode: _cachedLicense!.keyCode,
              expiresAt: _cachedLicense!.expiresAt,
              status: LicenseStatus.cached,
            ));
            return LicenseStatus.cached;
          }
        }
        return LicenseStatus.invalid;
      }

      final data = response.data as Map<String, dynamic>;
      final status = _parseStatus(data['status'] as String);
      final expiresAt = data['expires_at'] != null
          ? DateTime.tryParse(data['expires_at'])
          : null;
      final keyCode = data['key_code'] as String?;

      await _saveCache(LicenseCache(
        keyCode: keyCode,
        expiresAt: expiresAt,
        status: status,
      ));

      return status;
    } catch (e) {
      debugPrint('[LicenseService] validate error: $e');
      // Return cached status if available
      if (_cachedLicense != null && _cachedLicense!.expiresAt != null) {
        if (_cachedLicense!.expiresAt!.isAfter(DateTime.now())) {
          return LicenseStatus.cached;
        }
      }
      return LicenseStatus.invalid;
    }
  }

  /// Activate a license key by calling the Supabase Edge Function.
  Future<LicenseStatus> activate(String keyCode) async {
    final user = _client.auth.currentUser;
    if (user == null) return LicenseStatus.unlicensed;

    final fingerprint = DeviceFingerprintService.instance.fingerprint;

    try {
      final response = await _client.functions.invoke(
        'activate-license',
        body: {
          'key_code': keyCode.toUpperCase(),
          'device_fingerprint': fingerprint,
        },
      );

      if (response.status != 200) {
        final data = response.data as Map<String, dynamic>?;
        final error = data?['error'] as String? ?? 'Activation failed';
        debugPrint('[LicenseService] activate failed: $error');
        if (error.contains('already activated on another device') ||
            error.contains('already activated with another key')) {
          return LicenseStatus.deviceLimitReached;
        }
        return LicenseStatus.invalid;
      }

      final data = response.data as Map<String, dynamic>;
      final status = _parseStatus(data['status'] as String);
      final expiresAt = data['expires_at'] != null
          ? DateTime.tryParse(data['expires_at'])
          : null;

      await _saveCache(LicenseCache(
        keyCode: keyCode.toUpperCase(),
        expiresAt: expiresAt,
        status: status,
      ));

      return status;
    } catch (e) {
      debugPrint('[LicenseService] activate error: $e');
      return LicenseStatus.invalid;
    }
  }

  /// Deactivate current device from the license key.
  Future<bool> deactivate() async {
    final user = _client.auth.currentUser;
    if (user == null || _cachedLicense?.keyCode == null) return false;

    final fingerprint = DeviceFingerprintService.instance.fingerprint;

    try {
      final response = await _client.functions.invoke(
        'deactivate-device',
        body: {
          'device_fingerprint': fingerprint,
        },
      );

      if (response.status == 200) {
        await clearCache();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[LicenseService] deactivate error: $e');
      return false;
    }
  }

  LicenseStatus _parseStatus(String? status) {
    switch (status) {
      case 'active':
        return LicenseStatus.active;
      case 'expired':
        return LicenseStatus.expired;
      case 'revoked':
        return LicenseStatus.revoked;
      case 'device_limit_reached':
        return LicenseStatus.deviceLimitReached;
      default:
        return LicenseStatus.invalid;
    }
  }
}
