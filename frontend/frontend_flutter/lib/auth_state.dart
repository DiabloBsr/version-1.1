// lib/auth_state.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'utils/secure_storage.dart';
import 'services/auth_service.dart';

class AuthState extends ChangeNotifier {
  // Public flags used throughout the app and router
  bool loggedIn = false;
  String? role;
  String? userEmail;

  // Profile fields
  String? firstName;
  String? lastName;
  String? fullName;

  bool _initialized = false;
  bool get initialized => _initialized;

  String? get email => userEmail;

  StreamSubscription<bool>? _authSubscription;

  AuthState() {
    // Subscribe to AuthService auth state changes so the router can refresh immediately
    try {
      _authSubscription = AuthService.authStateChanges.listen((loggedInNow) {
        // If AuthService signals a logout, mark locally and notify
        if (loggedInNow == false) {
          markLoggedOutSync();
        } else {
          // On login signal, re-sync tokens/profile from storage
          // Note: do not await here to avoid blocking the listener
          initFromStorage();
        }
      });
    } catch (e, st) {
      debugPrint('[AuthState] subscription error: $e\n$st');
    }
  }

  /// Clean up subscription when the AuthState is disposed
  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> initFromStorage() async {
    try {
      final access = await SecureStorage.read('access');
      loggedIn = access != null && access.isNotEmpty;

      role = await SecureStorage.read('role');

      userEmail = await SecureStorage.read('email');

      // Attempt to load profile if logged in and no profile cached
      if (loggedIn && (firstName == null && fullName == null)) {
        unawaited(loadProfileFromApi());
      }

      debugPrint(
          '[AuthState] initFromStorage loggedIn=$loggedIn userEmail=$userEmail role=$role');
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
    role = null;
    userEmail = null;
    firstName = null;
    lastName = null;
    fullName = null;
    debugPrint('[AuthState] clearAll');
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

  Future<void> setUserEmail(String? email) async {
    userEmail = email;
    if (email == null) {
      await SecureStorage.delete('email');
      debugPrint('[AuthState] setUserEmail -> null');
    } else {
      await SecureStorage.write('email', email);
      debugPrint('[AuthState] setUserEmail -> $email');
      await _createProfileIfNeeded(email);
      // after setting email, attempt to fetch profile
      unawaited(loadProfileFromApi());
    }
    notifyListeners();
  }

  // ---- Profile fetching helper ----
  /// Charge le profil utilisateur depuis l'API backend si possible.
  /// Attend un endpoint retournant { first_name, last_name, full_name } ou champs similaires.
  Future<void> loadProfileFromApi() async {
    try {
      final accessToken = await SecureStorage.read('access');
      if (accessToken == null || accessToken.isEmpty) return;

      // ADAPTEZ CETTE URL À VOTRE BACKEND RÉEL
      final url = Uri.parse('https://your-backend.com/api/profile/me/');
      final headers = {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final res = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        // Normalisation : essaye plusieurs clés possibles
        firstName = (data['first_name'] ??
                data['given_name'] ??
                data['prenom'] ??
                data['firstName'])
            ?.toString();
        lastName = (data['last_name'] ??
                data['family_name'] ??
                data['nom'] ??
                data['lastName'])
            ?.toString();
        fullName = (data['full_name'] ??
                data['name'] ??
                data['display_name'] ??
                data['fullName'])
            ?.toString();

        // Si fullName absent mais first+last présents, compose
        if ((fullName == null || fullName!.isEmpty) &&
            (firstName?.isNotEmpty == true || lastName?.isNotEmpty == true)) {
          fullName =
              '${firstName ?? ''}${firstName != null && lastName != null ? ' ' : ''}${lastName ?? ''}'
                  .trim();
        }

        debugPrint(
            '[AuthState] loadProfileFromApi -> firstName=$firstName lastName=$lastName fullName=$fullName');
        notifyListeners();
      } else {
        debugPrint('[AuthState] loadProfileFromApi non-200: ${res.statusCode}');
      }
    } catch (e, st) {
      debugPrint('[AuthState] loadProfileFromApi error: $e\n$st');
    }
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

  /// Mark logged out synchronously and notify listeners so GoRouter refreshes immediately.
  void markLoggedOutSync() {
    loggedIn = false;
    role = null;
    userEmail = null;
    firstName = null;
    lastName = null;
    fullName = null;
    debugPrint('[AuthState] markLoggedOutSync -> loggedIn=false');
    notifyListeners();
  }
}
