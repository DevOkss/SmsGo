import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import '../models/github_release.dart';
import '../services/update_service.dart';
import '../services/version_service.dart';

/// States of the update lifecycle.
enum UpdateStatus {
  /// No update check has been performed yet.
  idle,

  /// Currently checking for updates.
  checking,

  /// An update is available.
  updateAvailable,

  /// Currently downloading the update.
  downloading,

  /// Download complete, ready to install.
  downloadComplete,

  /// Currently verifying checksum.
  verifying,

  /// Installation has been triggered.
  installing,

  /// The app is up to date.
  upToDate,

  /// An error occurred during the update process.
  error,

  /// User dismissed the update dialog.
  dismissed,
}

/// Manages the update state for the application.
///
/// Integrates with [UpdateService] to perform the actual update operations
/// and exposes state for UI consumption via Provider.
class UpdateProvider extends ChangeNotifier {
  final _updateService = UpdateService.instance;
  final _versionService = VersionService.instance;

  UpdateStatus _status = UpdateStatus.idle;
  GitHubRelease? _latestRelease;
  double _downloadProgress = 0.0;
  String? _errorMessage;
  String? _downloadedApkPath;

  // Getters
  UpdateStatus get status => _status;
  GitHubRelease? get latestRelease => _latestRelease;
  double get downloadProgress => _downloadProgress;
  String? get errorMessage => _errorMessage;
  String? get downloadedApkPath => _downloadedApkPath;

  String get currentVersion => _versionService.version;
  String get currentBuildNumber => _versionService.buildNumber;
  String? get commitHash => _versionService.commitHash;
  String? get buildDate => _versionService.buildDate;

  bool get isUpdateAvailable => _status == UpdateStatus.updateAvailable;
  bool get isDownloading => _status == UpdateStatus.downloading;
  bool get isChecking => _status == UpdateStatus.checking;
  bool get isUpToDate => _status == UpdateStatus.upToDate;
  bool get hasError => _status == UpdateStatus.error;

  /// Check for updates. Respects throttling unless [force] is true.
  ///
  /// This is the primary method called on app startup, resume, and
  /// manual check from Settings.
  Future<void> checkForUpdate({bool force = false}) async {
    if (_status == UpdateStatus.checking) return;

    _status = UpdateStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final release = await _updateService.checkForUpdate(force: force);

      if (release != null && release.hasApk) {
        _latestRelease = release;
        _status = UpdateStatus.updateAvailable;
      } else {
        _status = UpdateStatus.upToDate;
      }
    } catch (e) {
      _errorMessage = 'Failed to check for updates: $e';
      _status = UpdateStatus.error;
    }

    notifyListeners();
  }

  /// Download the available update.
  ///
  /// Shows download progress via [downloadProgress].
  /// On success, transitions to [UpdateStatus.downloadComplete].
  Future<void> downloadUpdate() async {
    if (_latestRelease == null || !_latestRelease!.hasApk) return;

    _status = UpdateStatus.downloading;
    _downloadProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      _downloadedApkPath = await _updateService.downloadUpdate(
        _latestRelease!.apkUrl,
        onProgress: (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );

      _status = UpdateStatus.verifying;
      notifyListeners();

      // Verify checksum if available
      final verified = await _updateService.verifyChecksum(
        _downloadedApkPath!,
        expectedHash: _latestRelease!.sha256,
      );

      if (!verified) {
        _errorMessage = 'File verification failed. The download may be corrupted.';
        _status = UpdateStatus.error;
        notifyListeners();
        return;
      }

      _status = UpdateStatus.downloadComplete;
    } catch (e) {
      _errorMessage = 'Download failed: $e';
      _status = UpdateStatus.error;
    }

    notifyListeners();
  }

  /// Install the downloaded update.
  ///
  /// Launches the system package installer.
  Future<void> installUpdate() async {
    if (_downloadedApkPath == null) return;

    _status = UpdateStatus.installing;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _updateService.installUpdate(_downloadedApkPath!);

      if (result.type != ResultType.done) {
        _errorMessage = 'Failed to open installer: ${result.message}';
        _status = UpdateStatus.error;
        notifyListeners();
        return;
      }

      // After successful install prompt, attempt restart
      _updateService.restartApp();
    } catch (e) {
      _errorMessage = 'Installation failed: $e';
      _status = UpdateStatus.error;
    }

    notifyListeners();
  }

  /// Download and install in one flow (for "Update Now" button).
  Future<void> downloadAndInstall() async {
    await downloadUpdate();
    if (_status == UpdateStatus.downloadComplete) {
      await installUpdate();
    }
  }

  /// Skip this version (user chose "Later").
  Future<void> skipUpdate() async {
    if (_latestRelease != null) {
      await _updateService.skipVersion(_latestRelease!.version);
    }
    _status = UpdateStatus.dismissed;
    notifyListeners();
  }

  /// Reset to idle state (for manual re-check).
  void reset() {
    _status = UpdateStatus.idle;
    _latestRelease = null;
    _downloadProgress = 0.0;
    _errorMessage = null;
    _downloadedApkPath = null;
    notifyListeners();
  }
}
