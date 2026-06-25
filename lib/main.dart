import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'core/constants/app_theme.dart';
import 'providers/campaign_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/messaging_provider.dart';
import 'providers/notes_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/update_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/license_provider.dart';

import 'features/auth/auth_gate.dart';
import 'splash_screen.dart';
import 'database/supabase.dart';
import 'services/device_fingerprint_service.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';
import 'services/version_service.dart';

final _lightTheme = AppTheme.light();
final _darkTheme = AppTheme.dark();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load();

  // Initialize Supabase
  await SupabaseClientFactory.init();

  // Initialize device fingerprint
  await DeviceFingerprintService.instance.init();

  // Initialize background service early so notification channel is ready
  await BulkSendingBackgroundService.instance.init();

  // Initialize notification service for incoming SMS notifications
  NotificationService.instance.init();

  // Initialize version service for reading package version info
  await VersionService.instance.init();

  final themeProvider = ThemeProvider();
  await themeProvider.loadMode();

  runApp(SmsGoApp(themeProvider: themeProvider));
}

class SmsGoApp extends StatefulWidget {
  final ThemeProvider themeProvider;
  const SmsGoApp({super.key, required this.themeProvider});

  @override
  State<SmsGoApp> createState() => _SmsGoAppState();
}

class _SmsGoAppState extends State<SmsGoApp> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.themeProvider),
        ChangeNotifierProvider(create: (_) => CampaignProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => MessagingProvider()),
        ChangeNotifierProvider(create: (_) => NotesProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => LicenseProvider()..initialize()),
      ],
      child: Selector<ThemeProvider, ThemeMode>(
        selector: (_, provider) => provider.mode,
        builder: (_, themeMode, __) => MaterialApp(
          title: 'SmsGo',
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: themeMode,
          home: _splashDone
              ? const AuthGate()
              : SplashScreen(
                  onFinished: () {
                    setState(() => _splashDone = true);
                  },
                ),
        ),
      ),
    );
  }
}
