import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_theme.dart';
import 'core/permissions/permissions_service.dart';
import 'features/campaign/campaign_sceen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/messaging/messaging_screen.dart';
import 'features/notes/note_screen.dart';
import 'features/settings/setting_screen.dart';
import 'providers/update_provider.dart';
import 'features/settings/widgets/update_dialog.dart';
import 'features/settings/widgets/download_progress_widget.dart';
import 'services/sms_import_gateway.dart';
import 'services/native_sms_import_controller.dart';
import 'core/widgets/license_enforcement_banner.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  bool _wasDefault = false;
  bool _permissionsRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_permissionsRequested) {
        _permissionsRequested = true;
        try {
          await PermissionsService.requestSmsPermissions();
        } catch (_) {}
      }
      if (Platform.isAndroid) {
        _wasDefault = await SmsImportGateway.isDefaultSmsApp();
        _checkDefaultSmsAndImport();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed) return;

    if (mounted) {
      final provider = context.read<UpdateProvider>();
      await provider.checkForUpdate();
      if (provider.isUpdateAvailable && provider.latestRelease != null && mounted) {
        final shouldUpdate = await UpdateDialog.show(context, provider.latestRelease!) ?? false;
        if (shouldUpdate && mounted) {
          DownloadProgressWidget.show(context);
          await provider.downloadAndInstall();
        }
      }
    }

    if (!Platform.isAndroid) return;

    final isDefault = await SmsImportGateway.isDefaultSmsApp();
    if (isDefault && !_wasDefault) {
      _wasDefault = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sms_was_default_before', true);
      if (!mounted) return;
      await _importAllSmsSilent();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversations imported successfully')),
        );
      }
    } else if (!isDefault) {
      _wasDefault = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sms_was_default_before', false);
    }
  }

  Future<void> _checkDefaultSmsAndImport() async {
    final isDefault = await SmsImportGateway.isDefaultSmsApp();
    debugPrint('[SmsGo] _checkDefaultSmsAndImport: isDefault=$isDefault');

    final prefs = await SharedPreferences.getInstance();

    if (isDefault) {
      final wasDefaultBefore = prefs.getBool('sms_was_default_before') ?? false;

      if (!wasDefaultBefore) {
        await _importAllSms();
        await prefs.setBool('sms_import_initial_done', true);
        await prefs.setBool('sms_was_default_before', true);
      } else {
        debugPrint('[SmsGo] Already imported, skipping');
      }
      return;
    }

    await prefs.setBool('sms_was_default_before', false);

    if (!mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 48, color: AppColors.primary),
        title: const Text('Set as Default SMS App'),
        content: const Text(
          'SmsGo needs to be your default SMS app to import existing conversations '
          'and receive incoming messages.\n\n'
          'You can switch back to your previous SMS app anytime in system settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Set as Default'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    SmsImportGateway.requestDefaultSmsAppForPackage(null).catchError((_) => false);

    await Future.delayed(const Duration(seconds: 2));
    final isNowDefault = await SmsImportGateway.isDefaultSmsApp();
    debugPrint('[SmsGo] After role request: isNowDefault=$isNowDefault');
    if (!isNowDefault) return;

    await _importAllSms();
    await prefs.setBool('sms_import_initial_done', true);
    await prefs.setBool('sms_was_default_before', true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conversations imported successfully')),
    );
  }

  Future<void> _importAllSms() async {
    debugPrint('[SmsGo] _importAllSms: starting import');
    if (!mounted) {
      debugPrint('[SmsGo] _importAllSms: not mounted, aborting');
      return;
    }

    final progressNotifier = ValueNotifier<int>(0);
    final totalNotifier = ValueNotifier<int>(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportProgressDialog(
        progressNotifier: progressNotifier,
        totalNotifier: totalNotifier,
      ),
    );

    try {
      final controller = NativeSmsImportController();
      await controller.importAll(
        types: ['inbox', 'sent'],
        onProgress: (current, totalMessages) {
          progressNotifier.value = current;
          totalNotifier.value = totalMessages;
        },
      );
      debugPrint('[SmsGo] _importAllSms: import completed');
    } catch (e) {
      debugPrint('[SmsGo] _importAllSms: import FAILED: $e');
    } finally {
      progressNotifier.dispose();
      totalNotifier.dispose();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _importAllSmsSilent() async {
    debugPrint('[SmsGo] _importAllSmsSilent: starting silent import');
    try {
      final controller = NativeSmsImportController();
      await controller.importAll(types: ['inbox', 'sent']);
      debugPrint('[SmsGo] _importAllSmsSilent: import completed');
    } catch (e) {
      debugPrint('[SmsGo] _importAllSmsSilent: import FAILED: $e');
    }
  }

  int _index = 0;

  final _screens = const [
    DashboardScreen(),
    MessagingScreen(),
    CampaignsScreen(),
    NotesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const LicenseEnforcementBanner(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.send_outlined),
            selectedIcon: Icon(Icons.send_rounded),
            label: 'Messaging',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign_rounded),
            label: 'Campaigns',
          ),
          NavigationDestination(
            icon: Icon(Icons.note_outlined),
            selectedIcon: Icon(Icons.note_rounded),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _ImportProgressDialog extends StatelessWidget {
  final ValueNotifier<int> progressNotifier;
  final ValueNotifier<int> totalNotifier;

  const _ImportProgressDialog({
    required this.progressNotifier,
    required this.totalNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SizedBox(
        height: 110,
        child: ValueListenableBuilder<int>(
          valueListenable: totalNotifier,
          builder: (_, total, __) {
            return ValueListenableBuilder<int>(
              valueListenable: progressNotifier,
              builder: (_, progress, __) {
                final pct = total > 0 ? (progress * 100 ~/ total) : 0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      total > 0
                          ? 'Importing conversations... $progress / $total ($pct%)'
                          : 'Loading messages...',
                    ),
                    const SizedBox(height: 8),
                    if (total > 0)
                      LinearProgressIndicator(
                        value: progress / total,
                        backgroundColor: Colors.grey.shade200,
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
