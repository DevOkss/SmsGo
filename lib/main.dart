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
import 'database/supabase.dart';
import 'services/device_fingerprint_service.dart';

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
          home: const AuthGate(),
        ),
      ),
    );
  }
}
