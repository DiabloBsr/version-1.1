import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'utils/secure_storage.dart';

class AuthState extends ChangeNotifier {
  bool loggedIn = false;
  bool otpVerified = false;
  String? role;
  bool? mfaEnabled;
  String? userEmail;

  AuthState();

  Future<void> initFromStorage() async {
    final access = await SecureStorage.read('access');
    loggedIn = access != null && access.isNotEmpty;

    final otp = await SecureStorage.read('otp_verified');
    otpVerified = otp == 'true';

    role = await SecureStorage.read('role');
    final me = await SecureStorage.read('mfa_enabled');
    mfaEnabled = me == null ? null : (me == 'true');

    userEmail = await SecureStorage.read('email');

    debugPrint(
      '[AuthState] initFromStorage loggedIn=$loggedIn otpVerified=$otpVerified role=$role mfaEnabled=$mfaEnabled userEmail=$userEmail',
    );

    notifyListeners();
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
