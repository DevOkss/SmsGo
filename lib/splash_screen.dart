import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/update_provider.dart';
import 'features/settings/widgets/update_dialog.dart';
import 'features/settings/widgets/download_progress_widget.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Trigger initial update check after a short delay (non-blocking)
    Timer(const Duration(milliseconds: 500), () {
      _checkForUpdates();
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    if (!mounted) return;

    try {
      final provider = context.read<UpdateProvider>();
      await provider.checkForUpdate();

      if (!mounted) return;

      if (provider.isUpdateAvailable && provider.latestRelease != null) {
        final shouldUpdate = await UpdateDialog.show(context, provider.latestRelease!) ?? false;
        if (shouldUpdate && mounted) {
          DownloadProgressWidget.show(context);
          await provider.downloadAndInstall();
        }
      }
    } catch (_) {
      // Silently ignore update check failures during splash
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Image.asset(
          'assets/splash_screen.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
