import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

enum AuthPhase { signedOut, verifying, signedIn }

/// Account state: sign-up with email verification, sign-in, "keep me signed in".
class AuthStore extends ChangeNotifier {
  AuthStore(this._auth) {
    _sub = _auth?.onAuthStateChange.listen((_) {
      // Signing in (including from the verification link) ends the wait for verification.
      if (_auth.currentSession != null && pendingEmail != null) {
        pendingEmail = null;
        _savePrefs();
      }
      notifyListeners();
    });
  }

  static const _keepKey = 'owned/auth/keepSignedIn';
  static const _emailKey = 'owned/auth/lastEmail';
  static const _pendingKey = 'owned/auth/pendingEmail';

  /// Null when Supabase isn't configured for this build.
  final GoTrueClient? _auth;
  StreamSubscription<AuthState>? _sub;

  /// Signed up but not yet verified.
  String? pendingEmail;

  /// The email last used on this device, to prefill sign-in.
  String lastEmail = '';
  bool keepSignedIn = true;

  User? get user => _auth?.currentSession?.user;

  AuthPhase get phase => user != null
      ? AuthPhase.signedIn
      : pendingEmail != null
      ? AuthPhase.verifying
      : AuthPhase.signedOut;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    keepSignedIn = prefs.getBool(_keepKey) ?? true;
    lastEmail = prefs.getString(_emailKey) ?? '';
    pendingEmail = prefs.getString(_pendingKey);
    // "Keep me signed in" was off: the previous session ends when the app is reopened.
    if (!keepSignedIn && user != null) await _auth!.signOut();
    notifyListeners();
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepKey, keepSignedIn);
    await prefs.setString(_emailKey, lastEmail);
    if (pendingEmail == null) {
      await prefs.remove(_pendingKey);
    } else {
      await prefs.setString(_pendingKey, pendingEmail!);
    }
  }

  /// Creates the account and sends the verification email. Returns an error message, or null.
  Future<String?> signUp(String email, String password) async {
    try {
      final res = await _auth!.signUp(
        email: email,
        password: password,
        emailRedirectTo: authRedirectUrl,
      );
      lastEmail = email;
      if (res.session == null) pendingEmail = email;
      await _savePrefs();
      notifyListeners();
      return null;
    } catch (e) {
      return _message(e);
    }
  }

  /// Returns an error message, or null when signed in (or when the email still needs verifying).
  Future<String?> signIn(
    String email,
    String password, {
    required bool keep,
  }) async {
    try {
      keepSignedIn = keep;
      lastEmail = email;
      await _auth!.signInWithPassword(email: email, password: password);
      pendingEmail = null;
      await _savePrefs();
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      if (e.code == 'email_not_confirmed') {
        pendingEmail = email;
        await _savePrefs();
        notifyListeners();
        return null;
      }
      return _message(e);
    } catch (e) {
      return _message(e);
    }
  }

  Future<String?> resendVerification() async {
    try {
      await _auth!.resend(
        type: OtpType.signup,
        email: pendingEmail,
        emailRedirectTo: authRedirectUrl,
      );
      return null;
    } catch (e) {
      return _message(e);
    }
  }

  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth!.resetPasswordForEmail(email, redirectTo: authRedirectUrl);
      return null;
    } catch (e) {
      return _message(e);
    }
  }

  /// Leave the "check your email" screen, e.g. to sign in after verifying on another device.
  Future<void> backToSignIn() async {
    pendingEmail = null;
    await _savePrefs();
    notifyListeners();
  }

  Future<void> signOut() async {
    await _auth?.signOut();
    notifyListeners();
  }

  String _message(Object e) {
    if (e is AuthException) {
      return switch (e.code) {
        'invalid_credentials' => 'Email or password is incorrect.',
        'user_already_exists' || 'email_exists' =>
          'An account with this email already exists. Sign in instead.',
        'weak_password' => e.message,
        'email_address_invalid' => 'That email address doesn’t look right.',
        'over_email_send_rate_limit' || 'over_request_rate_limit' =>
          'Too many attempts. Wait a minute, then try again.',
        _ => e.message,
      };
    }
    if (e is SocketException ||
        e is TimeoutException ||
        e is AuthRetryableFetchException) {
      return "Couldn't reach the server. Check your connection and try again.";
    }
    return 'Something went wrong. Try again.';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
