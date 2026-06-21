import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../models/github_release.dart';
import 'version_service.dart';
import 'github_release_service.dart';

/// Orchestrates the update flow: check, download, verify, install, restart.
///
/// Security measures:
/// - All downloads over HTTPS only
/// - SHA-256 checksum verification before installation
/// - Release metadata validation
/// - No hardcoded secrets (uses public GitHub API)
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  final _releaseService = GitHubReleaseService.instance;
  final _versionService = VersionService.instance;
  final _dio = Dio();

  /// Check if an update is available.
  ///
  /// Returns the [GitHubRelease] if an update is available, null otherwise.
  /// Respects the throttling interval unless [force] is true.
  Future<GitHubRelease?> checkForUpdate({bool force = false}) async {
    if (!force) {
      final canCheck = await _canCheckNow();
      if (!canCheck) return null;
    }

    final release = await _releaseService.fetchLatestRelease();
    if (release == null || !release.hasApk) return null;

    // Compare versions
    final isNewer = _versionService.isOlderThan(release.version);

    if (!isNewer) {
      await _recordCheckTime();
      return null;
    }

    // Check if user skipped this specific version
    final skippedVersion = await _getSkippedVersion();
    if (skippedVersion == release.version && !force) {
      return null;
    }

    await _recordCheckTime();
    return release;
  }

  /// Download the APK with progress tracking.
  ///
  /// [url] must be an HTTPS URL.
  /// [onProgress] is called with download progress (0.0 to 1.0).
  /// Returns the local file path on success, throws on failure.
  Future<String> downloadUpdate(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    // Security: enforce HTTPS
    if (!url.startsWith('https://')) {
      throw UpdateException('Download URL must use HTTPS');
    }

    final dir = await getTemporaryDirectory();
    final apkPath = '${dir.path}/smsgo_update.apk';

    try {
      final response = await _dio.download(
        url,
        apkPath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          headers: {'User-Agent': 'SmsGo-UpdateChecker'},
        ),
      );

      if (response.statusCode == 200) {
        return apkPath;
      }
      throw UpdateException('Download failed with status ${response.statusCode}');
    } on DioException catch (e) {
      throw UpdateException('Download failed: ${e.message}');
    }
  }

  /// Verify the downloaded APK's SHA-256 checksum.
  ///
  /// If [expectedHash] is null or empty, verification is skipped with a warning.
  /// Returns true if verification passes or is skipped.
  Future<bool> verifyChecksum(String apkPath, {String? expectedHash}) async {
    if (expectedHash == null || expectedHash.isEmpty) {
      debugPrint('[UpdateService] WARNING: No SHA-256 hash provided, skipping verification');
      return true;
    }

    try {
      final file = File(apkPath);
      if (!await file.exists()) {
        throw UpdateException('APK file not found');
      }

      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      final computedHash = digest.toString();

      if (computedHash.toLowerCase() != expectedHash.toLowerCase()) {
        throw UpdateException(
          'Checksum mismatch: expected $expectedHash, got $computedHash',
        );
      }

      debugPrint('[UpdateService] SHA-256 verification passed');
      return true;
    } catch (e) {
      if (e is UpdateException) rethrow;
      throw UpdateException('Checksum verification failed: $e');
    }
  }

  /// Launch the APK installer using the system package installer.
  ///
  /// Returns the result type from [OpenFilex].
  Future<OpenResult> installUpdate(String apkPath) async {
    final result = await OpenFilex.open(apkPath);
    return result;
  }

  /// Restart the application after a successful update.
  void restartApp() {
    Restart.restartApp();
  }

  /// Skip a specific version (user chose "Later" for this version).
  Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.updateSkippedVersionKey, version);
  }

  /// Clear any skipped version (so next check will show it).
  Future<void> clearSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.updateSkippedVersionKey);
  }

  /// Get the currently skipped version.
  Future<String?> _getSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.updateSkippedVersionKey);
  }

  /// Check if enough time has passed since the last update check.
  Future<bool> _canCheckNow() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(AppConstants.lastUpdateCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final intervalHours = int.tryParse(
          dotenv.env[AppConstants.envUpdateCheckInterval] ?? '',
        ) ??
        AppConstants.defaultCheckIntervalHours;
    final intervalMs = intervalHours * 60 * 60 * 1000;
    return (now - lastCheck) >= intervalMs;
  }

  /// Record the current time as the last check timestamp.
  Future<void> _recordCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      AppConstants.lastUpdateCheckKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Custom exception for update-related errors.
class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);

  @override
  String toString() => 'UpdateException: $message';
}
