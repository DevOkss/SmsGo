import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Provides application version information.
///
/// Reads version data from `package_info_plus` which sources from
/// pubspec.yaml's `version` field (versionName + versionCode on Android).
class VersionService {
  VersionService._();
  static final VersionService instance = VersionService._();

  PackageInfo? _packageInfo;

  /// Initialize by reading package info. Call once at app startup.
  Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  /// Full version string from pubspec.yaml (e.g. "1.0.0+1").
  String get fullVersion => _packageInfo?.version ?? '0.0.0+0';

  /// Semantic version only (e.g. "1.0.0").
  String get version {
    final full = _packageInfo?.version ?? '0.0.0+0';
    final plusIndex = full.indexOf('+');
    return plusIndex > 0 ? full.substring(0, plusIndex) : full;
  }

  /// Build number only (e.g. "1").
  String get buildNumber => _packageInfo?.buildNumber ?? '0';

  /// Application name.
  String get appName => _packageInfo?.appName ?? 'SmsGo';

  /// Package name / application ID.
  String get packageName => _packageInfo?.packageName ?? 'com.example.smsgo';

  /// Git commit hash injected at build time via --dart-define=COMMIT_HASH=xxx.
  /// Returns null if not provided (e.g. during development).
  String? get commitHash {
    try {
      // This will be set via --dart-define during CI/CD builds.
      // In development, it returns null.
      const hash = String.fromEnvironment('COMMIT_HASH', defaultValue: '');
      return hash.isEmpty ? null : hash;
    } catch (_) {
      return null;
    }
  }

  /// Build date injected at build time via --dart-define=BUILD_DATE=xxx.
  String? get buildDate {
    try {
      const date = String.fromEnvironment('BUILD_DATE', defaultValue: '');
      return date.isEmpty ? null : date;
    } catch (_) {
      return null;
    }
  }

  /// Check if the installed version is older than the given version string.
  bool isOlderThan(String otherVersion) {
    final currentParts = version.split('.');
    final otherParts = otherVersion.split('.');
    final length = currentParts.length > otherParts.length
        ? currentParts.length
        : otherParts.length;

    for (var i = 0; i < length; i++) {
      final current = i < currentParts.length
          ? (int.tryParse(currentParts[i]) ?? 0)
          : 0;
      final other = i < otherParts.length
          ? (int.tryParse(otherParts[i]) ?? 0)
          : 0;
      if (current < other) return true;
      if (current > other) return false;
    }
    return false;
  }

  /// Debug print of version info.
  void printInfo() {
    debugPrint('[VersionService] Version: $version');
    debugPrint('[VersionService] Build: $buildNumber');
    debugPrint('[VersionService] Commit: ${commitHash ?? "N/A"}');
    debugPrint('[VersionService] BuildDate: ${buildDate ?? "N/A"}');
  }
}
