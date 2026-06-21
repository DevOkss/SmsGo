import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import '../../core/constants/app_theme.dart';
import '../../core/widget/app_widgets.dart';
import '../../database/database.dart';
import '../../repositories/conversation_repository.dart';
import '../../providers/theme_provider.dart';
import '../../providers/update_provider.dart';
import '../../services/sms_import_gateway.dart';
import '../../services/native_sms_import_controller.dart';
import 'widgets/update_dialog.dart';
import 'widgets/download_progress_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDefaultSmsApp = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) _checkDefault();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-check every time screen is shown (IndexedStack keeps widget alive)
    if (Platform.isAndroid) _checkDefault();
  }

  Future<void> _checkDefault() async {
    final isDefault = await SmsImportGateway.isDefaultSmsApp();
    if (mounted) setState(() => _isDefaultSmsApp = isDefault);
  }

  Future<void> _setAsDefault() async {
    await SmsImportGateway.requestDefaultSmsAppForPackage(null);
    // Wait briefly for role grant, then check
    await Future.delayed(const Duration(seconds: 2));
    final isDefault = await SmsImportGateway.isDefaultSmsApp();
    if (mounted) setState(() => _isDefaultSmsApp = isDefault);
    if (isDefault && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set as default SMS app. Importing conversations...')),
      );
      await _importMessages();
    }
  }

  Future<void> _importMessages() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final controller = NativeSmsImportController();
      await controller.importAll(types: ['inbox', 'sent']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversations imported successfully'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _checkForUpdates() async {
    final provider = context.read<UpdateProvider>();
    await provider.checkForUpdate(force: true);

    if (!mounted) return;

    if (provider.isUpdateAvailable && provider.latestRelease != null) {
      final shouldUpdate = await UpdateDialog.show(context, provider.latestRelease!) ?? false;
      if (shouldUpdate && mounted) {
        DownloadProgressWidget.show(context);
        await provider.downloadAndInstall();
      }
    } else if (provider.isUpToDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your app is up to date'),
          backgroundColor: AppColors.success,
        ),
      );
    } else if (provider.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to check for updates'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('The Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('Appearance'),
          AppCard(
            child: Selector<ThemeProvider, bool>(
              selector: (_, provider) => provider.isDark,
              builder: (context, isDark, _) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dark Mode'),
                subtitle: const Text('Toggle light / dark theme'),
                secondary: const Icon(Icons.dark_mode_rounded),
                value: isDark,
                onChanged: (_) => context.read<ThemeProvider>().toggle(),
                activeThumbColor: AppColors.primary,
              ),
            ),
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 20),
            _SectionLabel('SMS'),
            AppCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _isDefaultSmsApp ? Icons.check_circle_rounded : Icons.chat_bubble_outline_rounded,
                      color: _isDefaultSmsApp ? AppColors.success : AppColors.darkSubtext,
                    ),
                    title: const Text('Default SMS App'),
                    subtitle: Text(_isDefaultSmsApp ? 'SmsGo is the default SMS app' : 'Not set as default'),
                    trailing: _isDefaultSmsApp
                        ? const StatusBadge(label: 'ACTIVE', color: AppColors.success)
                        : ElevatedButton(
                            onPressed: _setAsDefault,
                            child: const Text('Set'),
                          ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.download_rounded),
                    title: const Text('Import Messages'),
                    subtitle: const Text('Import SMS from device into conversations'),
                    trailing: _importing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            icon: const Icon(Icons.refresh_rounded),
                            onPressed: _isDefaultSmsApp ? _importMessages : null,
                            tooltip: _isDefaultSmsApp ? 'Import now' : 'Set as default first',
                          ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          _SectionLabel('DATA MANAGEMENT'),
          AppCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_sweep_rounded, color: AppColors.error),
              title: const Text('Delete Campaign Conversations'),
              subtitle: const Text('Remove all bulk send conversations, sessions, and send logs. Keeps leads and notes.'),
              onTap: () async {
                final confirmed = await ConfirmDialog.show(
                  context,
                  title: 'Delete campaign data?',
                  message: 'This will permanently delete all campaign conversations, sending sessions, and send logs. Campaign leads and notes will be preserved. This cannot be undone.',
                  confirmLabel: 'Delete',
                  confirmColor: AppColors.error,
                );
                if (!confirmed || !context.mounted) return;
                final db = await AppDatabase.instance.database;
                final repo = ConversationRepository(db);
                await repo.deleteCampaignConversations();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Campaign conversations, sessions, and logs deleted')),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel('About'),
          _AboutSection(onCheckUpdates: _checkForUpdates),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  final VoidCallback onCheckUpdates;

  const _AboutSection({required this.onCheckUpdates});

  @override
  Widget build(BuildContext context) {
    final updateProvider = context.watch<UpdateProvider>();
    final version = updateProvider.currentVersion;

    return AppCard(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('SmsGo'),
            subtitle: Text(
              'v$version',
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _UpdateStatusIcon(status: updateProvider.status),
            title: const Text('Check for Updates'),
            subtitle: Text(_updateStatusText(updateProvider)),
            trailing: updateProvider.isChecking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: onCheckUpdates,
                    tooltip: 'Check now',
                  ),
          ),
        ],
      ),
    );
  }

  String _updateStatusText(UpdateProvider provider) {
    switch (provider.status) {
      case UpdateStatus.updateAvailable:
        return 'Update available: v${provider.latestRelease?.version ?? "?"}';
      case UpdateStatus.upToDate:
        return 'Your app is up to date';
      case UpdateStatus.downloading:
        return 'Downloading... ${(provider.downloadProgress * 100).toInt()}%';
      case UpdateStatus.error:
        return provider.errorMessage ?? 'Update check failed';
      default:
        return 'Tap to check for updates';
    }
  }
}

class _UpdateStatusIcon extends StatelessWidget {
  final UpdateStatus status;
  const _UpdateStatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (status) {
      case UpdateStatus.updateAvailable:
        icon = Icons.system_update_rounded;
        color = AppColors.primary;
        break;
      case UpdateStatus.upToDate:
        icon = Icons.check_circle_rounded;
        color = AppColors.success;
        break;
      case UpdateStatus.downloading:
        icon = Icons.cloud_download_rounded;
        color = AppColors.primary;
        break;
      case UpdateStatus.error:
        icon = Icons.error_outline_rounded;
        color = AppColors.error;
        break;
      default:
        icon = Icons.update_rounded;
        color = AppColors.darkSubtext;
    }

    return Icon(icon, color: color);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
