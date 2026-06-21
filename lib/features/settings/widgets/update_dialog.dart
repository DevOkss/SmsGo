import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_theme.dart';
import '../../../models/github_release.dart';
import '../../../providers/update_provider.dart';

/// Non-intrusive dialog shown when an update is available.
///
/// Displays current version, latest version, and release notes.
/// Provides "Update Now" and "Later" actions.
class UpdateDialog extends StatelessWidget {
  final GitHubRelease release;

  const UpdateDialog({super.key, required this.release});

  /// Show the update dialog. Returns true if user chose to update.
  static Future<bool?> show(BuildContext context, GitHubRelease release) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UpdateDialog(release: release),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.system_update_rounded,
          size: 32,
          color: AppColors.primary,
        ),
      ),
      title: const Text('Update Available'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Version comparison
              _VersionRow(
                label: 'Current version',
                version: context.read<UpdateProvider>().currentVersion,
                isHighlighted: false,
              ),
              const SizedBox(height: 8),
              _VersionRow(
                label: 'Latest version',
                version: release.version,
                isHighlighted: true,
              ),
              if (release.commitHash != null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'Build: ${release.commitHash}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.darkSubtext,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Release notes
              if (release.releaseNotes.isNotEmpty) ...[
                Text(
                  'What\'s New',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    release.releaseNotes,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.5,
                    ),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Update Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  final String label;
  final String version;
  final bool isHighlighted;

  const _VersionRow({
    required this.label,
    required this.version,
    required this.isHighlighted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: isHighlighted
                ? BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: Text(
              'v$version',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight:
                    isHighlighted ? FontWeight.w700 : FontWeight.w500,
                color: isHighlighted ? AppColors.primary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
