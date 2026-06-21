import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_theme.dart';
import '../../../providers/update_provider.dart';

/// Progress widget shown during APK download and verification.
///
/// Displays a progress bar, percentage, and current status text.
/// Shown as a dialog or inline widget during the update flow.
class DownloadProgressWidget extends StatelessWidget {
  const DownloadProgressWidget({super.key});

  /// Show the download progress as a modal dialog.
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DownloadProgressWidget(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<UpdateProvider>(
      builder: (context, provider, _) {
        return AlertDialog(
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status icon
                _StatusIcon(status: provider.status),
                const SizedBox(height: 16),

                // Status text
                Text(
                  _statusText(provider),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Progress bar
                if (provider.isDownloading) ...[
                  LinearProgressIndicator(
                    value: provider.downloadProgress > 0
                        ? provider.downloadProgress
                        : null,
                    backgroundColor: Colors.grey.shade200,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(provider.downloadProgress * 100).toInt()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.darkSubtext,
                    ),
                  ),
                ],

                // Verification spinner
                if (provider.status == UpdateStatus.verifying) ...[
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(height: 8),
                  Text(
                    'Verifying file integrity...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.darkSubtext,
                    ),
                  ),
                ],

                // Error message
                if (provider.hasError && provider.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 16, color: AppColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Download complete - show install prompt
                if (provider.status == UpdateStatus.downloadComplete) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 16, color: AppColors.success),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Download complete. Tap Install to proceed.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (provider.hasError)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            if (provider.status == UpdateStatus.downloadComplete)
              ElevatedButton.icon(
                onPressed: () async {
                  await provider.installUpdate();
                },
                icon: const Icon(Icons.install_mobile_rounded, size: 18),
                label: const Text('Install'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                ),
              ),
            if (provider.hasError)
              ElevatedButton.icon(
                onPressed: () async {
                  provider.reset();
                  await provider.downloadUpdate();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        );
      },
    );
  }

  String _statusText(UpdateProvider provider) {
    switch (provider.status) {
      case UpdateStatus.downloading:
        return 'Downloading update...';
      case UpdateStatus.verifying:
        return 'Verifying download...';
      case UpdateStatus.downloadComplete:
        return 'Download complete';
      case UpdateStatus.installing:
        return 'Opening installer...';
      case UpdateStatus.error:
        return 'Update failed';
      default:
        return 'Preparing download...';
    }
  }
}

class _StatusIcon extends StatelessWidget {
  final UpdateStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (status) {
      case UpdateStatus.downloading:
        icon = Icons.cloud_download_rounded;
        color = AppColors.primary;
        break;
      case UpdateStatus.verifying:
        icon = Icons.verified_user_rounded;
        color = AppColors.primary;
        break;
      case UpdateStatus.downloadComplete:
        icon = Icons.check_circle_rounded;
        color = AppColors.success;
        break;
      case UpdateStatus.installing:
        icon = Icons.install_mobile_rounded;
        color = AppColors.success;
        break;
      case UpdateStatus.error:
        icon = Icons.error_outline_rounded;
        color = AppColors.error;
        break;
      default:
        icon = Icons.hourglass_top_rounded;
        color = AppColors.darkSubtext;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 32, color: color),
    );
  }
}
