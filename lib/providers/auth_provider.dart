import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/error_utils.dart';
import '../services/auth_service.dart';

const _kPendingEmailKey = 'pending_verification_email';

/// Auth state exposed to the UI.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService.instance;

  AuthStatus _status = AuthStatus.uninitialized;
  AuthStatus get status => _status;

  /// Set to true when sign-in fails because email is not confirmed.
  /// AuthGate checks this to route to OTP verification.
  bool _emailNotConfirmed = false;
  bool get emailNotConfirmed => _emailNotConfirmed;

  /// The email that needs verification (set on sign-in or sign-up).
  String? _pendingVerificationEmail;
  String? get pendingVerificationEmail => _pendingVerificationEmail;

  User? get currentUser => _authService.currentUser;
  String? get userEmail => currentUser?.email;

  StreamSubscription<AuthState>? _authSub;

  Future<void> initialize() async {
    _authService.initialize();
    _status = _authService.status;

    // If no session, check if we have a persisted pending email from a prior sign-up.
    if (_status == AuthStatus.unauthenticated) {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString(_kPendingEmailKey);
      if (savedEmail != null && savedEmail.isNotEmpty) {
        _pendingVerificationEmail = savedEmail;
        _emailNotConfirmed = true;
      }
    }

    notifyListeners();

    _authSub = _authService.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;

      debugPrint('[AuthProvider] auth event: $event');

      switch (event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
          _emailNotConfirmed = false;
          _pendingVerificationEmail = null;
          await _clearPendingEmail();
          _status = AuthStatus.authenticated;
          break;
        case AuthChangeEvent.signedOut:
          _emailNotConfirmed = false;
          _pendingVerificationEmail = null;
          await _clearPendingEmail();
          _status = AuthStatus.unauthenticated;
          break;
        case AuthChangeEvent.passwordRecovery:
          _status = AuthStatus.authenticated;
          break;
        default:
          _emailNotConfirmed = false;
          _status = session != null
              ? AuthStatus.authenticated
              : AuthStatus.unauthenticated;
      }

      notifyListeners();
    });
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final response = await _authService.signUp(
        email: email,
        password: password,
        fullName: fullName,
      );
      // If email confirmation is required, session is null.
      // Set pending email so AuthGate can route to OTP.
      if (response.session == null) {
        _pendingVerificationEmail = email;
        _emailNotConfirmed = true;
        await _savePendingEmail(email);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AuthProvider] signUp error: $e');
      rethrow;
    }
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _authService.signIn(email: email, password: password);
      return null;
    } on AuthException catch (e) {
      if (e.message.contains('Email not confirmed')) {
        _pendingVerificationEmail = email;
        _emailNotConfirmed = true;
        await _savePendingEmail(email);
        notifyListeners();
        return null; // Don't show error — AuthGate will handle navigation
      }
      final message = e.message.contains('Invalid login credentials')
          ? 'Invalid email or password'
          : e.message;
      return message;
    } catch (e) {
      debugPrint('[AuthProvider] signIn error: $e');
      return friendlyError(e);
    }
  }

  /// Update password after recovery.
  Future<String?> updatePassword(String newPassword) async {
    try {
      await _authService.updatePassword(newPassword);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Failed to update password';
    }
  }

  Future<void> signOut() async {
    _emailNotConfirmed = false;
    _pendingVerificationEmail = null;
    await _authService.signOut();
  }

  /// Verify OTP code (signup or recovery).
  Future<String?> verifyOtp({
    required String email,
    required String token,
    required String type,
  }) async {
    try {
      await _authService.verifyOtp(
        email: email,
        token: token,
        type: type,
      );
      _emailNotConfirmed = false;
      _pendingVerificationEmail = null;
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('[AuthProvider] verifyOtp error: $e');
      return 'Verification failed';
    }
  }

  /// Send a password-recovery email (Supabase magic link).
  Future<String?> resendOtp({
    required String email,
    String type = 'recovery',
  }) async {
    try {
      await _authService.sendRecoveryOtp(email);
      return null;
    } catch (e) {
      debugPrint('[AuthProvider] resendOtp error: $e');
      return 'Failed to send recovery email';
    }
  }

  /// Resend signup verification OTP.
  Future<String?> resendSignupOtp(String email) async {
    try {
      await _authService.resendSignupOtp(email);
      return null;
    } catch (e) {
      debugPrint('[AuthProvider] resendSignupOtp error: $e');
      return 'Failed to resend verification code';
    }
  }

  Future<void> _savePendingEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingEmailKey, email);
  }

  Future<void> _clearPendingEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingEmailKey);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
