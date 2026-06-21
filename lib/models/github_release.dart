/// Model representing a GitHub Release with update metadata.
class GitHubRelease {
  final String version;
  final String? commitHash;
  final String? buildDate;
  final String apkUrl;
  final String? sha256;
  final String releaseNotes;
  final String publishedAt;
  final String? updateJsonUrl;

  const GitHubRelease({
    required this.version,
    this.commitHash,
    this.buildDate,
    required this.apkUrl,
    this.sha256,
    required this.releaseNotes,
    required this.publishedAt,
    this.updateJsonUrl,
  });

  /// Parse from GitHub Releases API response.
  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    final assets = json['assets'] as List<dynamic>? ?? [];
    String? apkUrl;
    String? sha256;
    String? updateJsonUrl;

    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      final url = asset['browser_download_url'] as String? ?? '';
      if (name.endsWith('.apk')) {
        apkUrl = url;
      } else if (name == 'update.json') {
        updateJsonUrl = url;
      }
    }

    // Extract version from tag_name (strip leading 'v' if present)
    var version = json['tag_name'] as String? ?? '';
    if (version.startsWith('v') || version.startsWith('V')) {
      version = version.substring(1);
    }

    // Try to extract commit hash from body or release name
    String? commitHash;
    final body = json['body'] as String? ?? '';
    final name = json['name'] as String? ?? '';
    final commitRegex = RegExp(r'Commit:\s*([a-f0-9]{7,40})', caseSensitive: false);
    final commitMatch = commitRegex.firstMatch('$body\n$name');
    if (commitMatch != null) {
      commitHash = commitMatch.group(1);
    }

    return GitHubRelease(
      version: version,
      commitHash: commitHash,
      buildDate: json['published_at'] as String?,
      apkUrl: apkUrl ?? '',
      sha256: sha256,
      releaseNotes: body,
      publishedAt: json['published_at'] as String? ?? '',
      updateJsonUrl: updateJsonUrl,
    );
  }

  /// Parse from update.json asset.
  factory GitHubRelease.fromUpdateJson(Map<String, dynamic> json, {String? fallbackApkUrl}) {
    return GitHubRelease(
      version: json['version'] as String? ?? '',
      commitHash: json['commit'] as String?,
      buildDate: json['buildDate'] as String?,
      apkUrl: json['apkUrl'] as String? ?? fallbackApkUrl ?? '',
      sha256: json['sha256'] as String?,
      releaseNotes: json['releaseNotes'] as String? ?? '',
      publishedAt: json['buildDate'] as String? ?? '',
    );
  }

  /// Compare versions semantically. Returns:
  /// - negative if this < other
  /// - 0 if equal
  /// - positive if this > other
  int compareTo(GitHubRelease other) => compareVersionStrings(version, other.version);

  /// Compare two version strings (e.g. "1.0.0" vs "1.1.0").
  static int compareVersionStrings(String a, String b) {
    final partsA = a.split('.');
    final partsB = b.split('.');
    final length = partsA.length > partsB.length ? partsA.length : partsB.length;

    for (var i = 0; i < length; i++) {
      final numA = i < partsA.length ? (int.tryParse(partsA[i]) ?? 0) : 0;
      final numB = i < partsB.length ? (int.tryParse(partsB[i]) ?? 0) : 0;
      if (numA != numB) return numA.compareTo(numB);
    }
    return 0;
  }

  bool get hasApk => apkUrl.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'version': version,
    'commit': commitHash,
    'buildDate': buildDate,
    'apkUrl': apkUrl,
    'sha256': sha256,
    'releaseNotes': releaseNotes,
  };

  @override
  String toString() => 'GitHubRelease(v$version, commit: $commitHash)';
}
