import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthStatus { uninitialized, authenticated, unauthenticated }

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _client = Supabase.instance.client;

  AuthStatus _status = AuthStatus.uninitialized;
  AuthStatus get status => _status;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  void initialize() {
    final session = _client.auth.currentSession;
    final user = _client.auth.currentUser;

    if (session != null && user != null) {
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    debugPrint('[AuthService] initialized: status=$_status');
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    // Check email uniqueness via database function before signing up.
    // Supabase silently handles duplicate emails differently depending on
    // confirmation settings, so we query auth.users directly.
    try {
      final exists = await _client
          .rpc('check_email_exists', params: {'email_to_check': email});
      if (exists == true) {
        throw AuthException(
          'A user with this email address has already been registered',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      // If the function doesn't exist yet, fall through and let signUp proceed
      debugPrint('[AuthService] check_email_exists RPC failed: $e');
    }

    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName ?? ''},
    );

    // If Supabase has email confirmation disabled, user gets a session immediately
    if (response.session != null) {
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    return response;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    _status = AuthStatus.authenticated;
    return response;
  }

  /// Send OTP for password recovery.
  Future<void> sendRecoveryOtp(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  /// Verify OTP (signup or recovery).
  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
    required String type,
  }) async {
    final response = await _client.auth.verifyOTP(
      email: email,
      token: token,
      type: type == 'signup' ? OtpType.signup : OtpType.recovery,
    );
    if (response.session != null) {
      _status = AuthStatus.authenticated;
    }
    return response;
  }

  /// Resend signup verification OTP.
  Future<void> resendSignupOtp(String email) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email,
    );
  }

  /// Update password (requires active session from recovery).
  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _status = AuthStatus.unauthenticated;
  }
}
