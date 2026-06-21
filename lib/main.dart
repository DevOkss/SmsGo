import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_theme.dart';
import 'core/permissions/permissions_service.dart';
import 'features/campaign/campaign_sceen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/messaging/messaging_screen.dart';
import 'features/notes/note_screen.dart';
import 'features/settings/setting_screen.dart';
import 'providers/campaign_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/messaging_provider.dart';
import 'providers/notes_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/update_provider.dart';
import 'services/sms_import_gateway.dart';
import 'services/native_sms_import_controller.dart';
import 'services/version_service.dart';
import 'services/github_release_service.dart';

import 'splash_screen.dart';
import 'services/notification_service.dart';

final _lightTheme = AppTheme.light();
final _darkTheme = AppTheme.dark();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load();

  // Initialize services
  await NotificationService.instance.init();
  await VersionService.instance.init();
  GitHubReleaseService.instance.init();

  final themeProvider = ThemeProvider();
  await themeProvider.loadMode();

  runApp(SmsGoApp(themeProvider: themeProvider));
}

class SmsGoApp extends StatelessWidget {
  final ThemeProvider themeProvider;
  const SmsGoApp({super.key, required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => CampaignProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => MessagingProvider()),
        ChangeNotifierProvider(create: (_) => NotesProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: Selector<ThemeProvider, ThemeMode>(
        selector: (_, provider) => provider.mode,
        builder: (_, themeMode, __) => MaterialApp(
          title: 'SmsGo',
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: themeMode,
          home: const SplashScreen(),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  bool _wasDefault = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PermissionsService.requestSmsPermissions();
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

    // Check for updates when app resumes from background
    if (mounted) {
      context.read<UpdateProvider>().checkForUpdate();
    }

    if (!Platform.isAndroid) return;

    final isDefault = await SmsImportGateway.isDefaultSmsApp();
    if (isDefault && !_wasDefault) {
      // App just became default — import messages silently
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
        // First time becoming default — import with progress dialog
        await _importAllSms();
        await prefs.setBool('sms_import_initial_done', true);
        await prefs.setBool('sms_was_default_before', true);
      } else {
        // Was default before and still is — no need to re-import
        debugPrint('[SmsGo] Already imported, skipping');
      }
      return;
    }

    // App is NOT default — mark that it's no longer default so next time it becomes
    // default again, it will re-import
    await prefs.setBool('sms_was_default_before', false);

    // Prompt user to set it
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

    if (proceed != true) {
      return;
    }

    // Fire-and-forget: open the system role dialog.
    SmsImportGateway.requestDefaultSmsAppForPackage(null).catchError((_) => false);

    // Wait briefly for potential activity recreation, then check state.
    await Future.delayed(const Duration(seconds: 2));
    final isNowDefault = await SmsImportGateway.isDefaultSmsApp();
    debugPrint('[SmsGo] After role request: isNowDefault=$isNowDefault');
    if (!isNowDefault) {
      return;
    }

    // Now default — import messages
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
      body: IndexedStack(
        index: _index,
        children: _screens,
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
