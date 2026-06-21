import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/constants/app_constants.dart';
import '../models/github_release.dart';

/// Client for fetching release information from GitHub Releases API.
///
/// Uses only public GitHub API endpoints — no authentication required.
/// All requests are over HTTPS.
class GitHubReleaseService {
  GitHubReleaseService._();
  static final GitHubReleaseService instance = GitHubReleaseService._();

  late final Dio _dio;

  /// GitHub API base URL.
  static const String _baseUrl = 'https://api.github.com';

  /// Initialize the Dio HTTP client.
  void init() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'SmsGo-UpdateChecker',
      },
    ));
  }

  /// Get the configured GitHub owner from .env or fallback to default.
  String get _owner =>
      dotenv.env[AppConstants.envGithubOwner] ??
      AppConstants.defaultGithubOwner;

  /// Get the configured GitHub repo from .env or fallback to default.
  String get _repo =>
      dotenv.env[AppConstants.envGithubRepo] ??
      AppConstants.defaultGithubRepo;

  /// Fetch the latest release from GitHub.
  ///
  /// Returns null if the request fails or no releases exist.
  Future<GitHubRelease?> fetchLatestRelease() async {
    try {
      final response = await _dio.get(
        '/repos/$_owner/$_repo/releases/latest',
      );

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        var release = GitHubRelease.fromJson(response.data as Map<String, dynamic>);

        // If update.json asset exists, fetch it for more accurate data
        if (release.updateJsonUrl != null) {
          final updateData = await _fetchUpdateJson(release.updateJsonUrl!);
          if (updateData != null) {
            release = GitHubRelease.fromUpdateJson(
              updateData,
              fallbackApkUrl: release.apkUrl,
            );
          }
        }

        return release;
      }
      return null;
    } on DioException catch (e) {
      // 404 = no releases yet, which is expected for new repos
      if (e.response?.statusCode == 404) {
        return null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch the update.json asset from a release.
  Future<Map<String, dynamic>?> _fetchUpdateJson(String url) async {
    try {
      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      // If response is a string (raw JSON), parse it
      if (response.statusCode == 200 && response.data is String) {
        return jsonDecode(response.data as String) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch all releases (for version history display if needed).
  Future<List<GitHubRelease>> fetchReleases({int perPage = 10}) async {
    try {
      final response = await _dio.get(
        '/repos/$_owner/$_repo/releases',
        queryParameters: {'per_page': perPage},
      );

      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .where((r) => r is Map<String, dynamic>)
            .map((r) => GitHubRelease.fromJson(r as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Get the download URL for a specific release's APK.
  String getDownloadUrl(String tagName) {
    return 'https://github.com/$_owner/$_repo/releases/download/$tagName/app-release.apk';
  }

  /// Get the releases page URL for manual download fallback.
  String getReleasesPageUrl() {
    return 'https://github.com/$_owner/$_repo/releases';
  }
}
