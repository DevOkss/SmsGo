import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/license_provider.dart';
import '../../services/auth_service.dart';
import '../../services/license_service.dart';
import '../../splash_screen.dart';
import '../../main_shell.dart';
import 'login_screen.dart';
import 'license_activation_screen.dart';
import 'otp_verification_screen.dart';

/// Routes the user based on auth + license state.
///
/// Flow:
/// - uninitialized → SplashScreen (loading)
/// - unauthenticated + emailNotConfirmed → OtpVerificationScreen
/// - unauthenticated → LoginScreen
/// - authenticated → LicenseGate → (active | expired+banner | unlicensed → activation)
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        switch (auth.status) {
          case AuthStatus.uninitialized:
            return const SplashScreen();
          case AuthStatus.unauthenticated:
            if (auth.emailNotConfirmed && auth.pendingVerificationEmail != null) {
              return OtpVerificationScreen(
                email: auth.pendingVerificationEmail!,
                type: 'signup',
              );
            }
            return const LoginScreen();
          case AuthStatus.authenticated:
            return const _LicenseGate();
        }
      },
    );
  }
}

/// Separate widget that listens to LicenseProvider.
class _LicenseGate extends StatelessWidget {
  const _LicenseGate();

  @override
  Widget build(BuildContext context) {
    return Consumer<LicenseProvider>(
      builder: (context, license, _) {
        switch (license.status) {
          case LicenseStatus.unknown:
            return const SplashScreen();
          case LicenseStatus.active:
          case LicenseStatus.cached:
            return const MainShell();
          case LicenseStatus.expired:
            return const MainShell(); // Banner shown in MainShell
          default:
            return const LicenseActivationScreen();
        }
      },
    );
  }
}
