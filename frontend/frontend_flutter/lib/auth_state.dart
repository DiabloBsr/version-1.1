// lib/auth_state.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'utils/secure_storage.dart';

class AuthState extends ChangeNotifier {
  // Public flags used throughout the app and router
  bool loggedIn = false;
  bool otpVerified = false;
  String? role;
  bool? mfaEnabled;
  String? userEmail;

  // Nouveautés pour connexion en deux étapes
  bool pendingLogin = false; // true après soumission identifiants si OTP requis
  String? pendingEmail; // email/username pour flow OTP
  String? pendingTempToken; // token temporaire / transaction id du backend

  // Internal initialization indicator used by router to avoid redirect loops
  bool _initialized = false;
  bool get initialized => _initialized;

  /// Expose email via `email` getter (router expects authState.email)
  String? get email => userEmail;

  AuthState();

  /// Charge l'état initial depuis SecureStorage. Appelle notifyListeners().
  Future<void> initFromStorage() async {
    try {
      final access = await SecureStorage.read('access');
      loggedIn = access != null && access.isNotEmpty;

      final otp = await SecureStorage.read('otp_verified');
      otpVerified = otp == 'true';

      role = await SecureStorage.read('role');
      final me = await SecureStorage.read('mfa_enabled');
      mfaEnabled = me == null ? null : (me == 'true');

      userEmail = await SecureStorage.read('email');

      // pending info are not persisted long-term; kept in-memory
      pendingLogin = false;
      pendingEmail = null;
      pendingTempToken = null;

      debugPrint(
        '[AuthState] initFromStorage loggedIn=$loggedIn otpVerified=$otpVerified role=$role mfaEnabled=$mfaEnabled userEmail=$userEmail',
      );
    } catch (e, st) {
      debugPrint('[AuthState] initFromStorage error: $e\n$st');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> setTokens(String access, String refresh) async {
    await SecureStorage.write('access', access);
    await SecureStorage.write('refresh', refresh);
    loggedIn = true;
    debugPrint('[AuthState] setTokens -> loggedIn=true');
    notifyListeners();
  }

  Future<void> clearAll() async {
    await SecureStorage.deleteAll();
    loggedIn = false;
    otpVerified = false;
    role = null;
    mfaEnabled = null;
    userEmail = null;
    pendingLogin = false;
    pendingEmail = null;
    pendingTempToken = null;
    debugPrint('[AuthState] clearAll');
    notifyListeners();
  }

  Future<void> setOtpVerified(bool v) async {
    otpVerified = v;
    await SecureStorage.write('otp_verified', v ? 'true' : 'false');
    debugPrint('[AuthState] setOtpVerified -> $v');
    notifyListeners();
  }

  Future<void> setRole(String? r) async {
    role = r;
    if (r == null) {
      await SecureStorage.delete('role');
      debugPrint('[AuthState] setRole -> null');
    } else {
      await SecureStorage.write('role', r);
      debugPrint('[AuthState] setRole -> $r');
    }
    notifyListeners();
  }

  Future<void> setMfaEnabled(bool? enabled) async {
    mfaEnabled = enabled;
    if (enabled == null) {
      await SecureStorage.delete('mfa_enabled');
      debugPrint('[AuthState] setMfaEnabled -> null');
    } else {
      await SecureStorage.write('mfa_enabled', enabled ? 'true' : 'false');
      debugPrint('[AuthState] setMfaEnabled -> $enabled');
    }
    notifyListeners();
  }

  Future<void> setUserEmail(String? email) async {
    userEmail = email;
    if (email == null) {
      await SecureStorage.delete('email');
      debugPrint('[AuthState] setUserEmail -> null');
    } else {
      await SecureStorage.write('email', email);
      debugPrint('[AuthState] setUserEmail -> $email');
      await _createProfileIfNeeded(email);
    }
    notifyListeners();
  }

  // ---- Flow two-step helpers ----

  /// Appelé après la première étape du login (username+password)
  /// Le backend peut renvoyer tokens ou indiquer otp_required avec temp_token
  Future<void> startPendingLogin({
    required String email,
    required String password,
    required Uri loginUri, // exemple: Uri.parse('http://.../auth/login/')
  }) async {
    pendingLogin = false;
    pendingEmail = null;
    pendingTempToken = null;
    notifyListeners();

    try {
      final res = await http.post(
        loginUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // Si backend renvoie tokens directement
        if (data['access'] != null && data['refresh'] != null) {
          await setTokens(data['access'], data['refresh']);
          await setUserEmail(email);
          if (data['mfa_enabled'] != null)
            await setMfaEnabled(data['mfa_enabled']);
          if (data['role'] != null) await setRole(data['role']);
          await setOtpVerified(true); // pas d'OTP requis
          return;
        }

        // Si backend demande OTP
        if (data['otp_required'] == true) {
          pendingLogin = true;
          pendingEmail = email;
          pendingTempToken = data['temp_token']?.toString();
          debugPrint('[AuthState] startPendingLogin -> pendingLogin=true');
          notifyListeners();
          return;
        }
      }

      debugPrint(
          '[AuthState] startPendingLogin failed: ${res.statusCode} ${res.body}');
    } catch (e) {
      debugPrint('[AuthState] startPendingLogin error: $e');
    }
  }

  /// Appelé après que l'utilisateur ait saisi le code OTP
  /// Le backend doit renvoyer les tokens définitifs
  Future<bool> confirmOtp({
    required String otpCode,
    required Uri verifyUri, // exemple: Uri.parse('http://.../auth/verify-otp/')
  }) async {
    if (!pendingLogin || pendingEmail == null) return false;

    try {
      final body = {
        'email': pendingEmail,
        'otp': otpCode,
        if (pendingTempToken != null) 'temp_token': pendingTempToken,
      };
      final res = await http.post(
        verifyUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['access'] != null && data['refresh'] != null) {
          await setTokens(data['access'], data['refresh']);
          await setUserEmail(pendingEmail);
          if (data['mfa_enabled'] != null)
            await setMfaEnabled(data['mfa_enabled']);
          if (data['role'] != null) await setRole(data['role']);
          await setOtpVerified(true);
          // clear pending
          pendingLogin = false;
          pendingEmail = null;
          pendingTempToken = null;
          notifyListeners();
          return true;
        }
      }

      debugPrint(
          '[AuthState] confirmOtp failed: ${res.statusCode} ${res.body}');
    } catch (e) {
      debugPrint('[AuthState] confirmOtp error: $e');
    }
    return false;
  }

  void cancelPendingLogin() {
    pendingLogin = false;
    pendingEmail = null;
    pendingTempToken = null;
    notifyListeners();
  }

  // ---- fin helpers ----

  Future<void> _createProfileIfNeeded(String email) async {
    final accessToken = await SecureStorage.read('access');
    if (accessToken == null || accessToken.isEmpty) return;

    final url = Uri.parse('https://your-backend.com/api/profile/');
    final headers = {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    };
    final body = jsonEncode({'email': email});

    try {
      final response = await http.post(url, headers: headers, body: body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint('[AuthState] Profile created for $email');
      } else if (response.statusCode == 409) {
        debugPrint('[AuthState] Profile already exists for $email');
      } else {
        debugPrint(
            '[AuthState] Profile creation failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[AuthState] Profile creation error: $e');
    }
  }
}
