import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import '../utils/secure_storage.dart';

class AuthService {
  static const String apiBase = 'http://127.0.0.1:8000/api/v1';

  static Future<Map<String, String>> _authHeaders({bool json = true}) async {
    final token = await SecureStorage.read('access');
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Try refresh using refresh token; return true if refreshed.
  /// If refresh fails with 401 (token_not_valid / blacklisted) we clear local tokens.
  static Future<bool> refreshTokens() async {
    final refresh = await SecureStorage.read('refresh');
    if (refresh == null || refresh.isEmpty) {
      debugPrint('[AuthService] refreshTokens: no refresh token');
      return false;
    }

    try {
      final res = await http
          .post(
            Uri.parse('$apiBase/token/refresh/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint(
          '[AuthService] refreshTokens: status ${res.statusCode} body=${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final access =
            (data['access'] as String?) ?? (data['access_token'] as String?);
        final refreshNew =
            (data['refresh'] as String?) ?? (data['refresh_token'] as String?);
        if (access != null && access.isNotEmpty) {
          await SecureStorage.write('access', access);
          if (refreshNew != null && refreshNew.isNotEmpty) {
            await SecureStorage.write('refresh', refreshNew);
            debugPrint('[AuthService] refreshTokens: updated refresh token');
          }
          debugPrint('[AuthService] refreshTokens: success, access updated');
          return true;
        } else {
          debugPrint('[AuthService] refreshTokens: 200 but no access in body');
        }
      } else {
        // If server says token invalid/blacklisted, wipe local tokens immediately
        if (res.statusCode == 401) {
          debugPrint(
              '[AuthService] refreshTokens: 401 — clearing local tokens');
          await SecureStorage.delete('access');
          await SecureStorage.delete('refresh');
        }
      }
    } catch (e, st) {
      debugPrint('[AuthService] refreshTokens error: $e\n$st');
    }
    return false;
  }

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      final res = await http
          .post(
            Uri.parse('$apiBase/token/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final access =
            (data['access'] as String?) ?? (data['access_token'] as String?);
        final refresh =
            (data['refresh'] as String?) ?? (data['refresh_token'] as String?);
        if (access != null && refresh != null) {
          await SecureStorage.write('access', access);
          await SecureStorage.write('refresh', refresh);
          debugPrint('[AuthService] login: tokens saved');
          return {'success': true, 'access': access, 'refresh': refresh};
        }
        return {'success': false, 'error': 'Tokens manquants'};
      }
      return {'success': false, 'error': res.body};
    } catch (e, st) {
      debugPrint('[AuthService] login error: $e\n$st');
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<void> logout() async {
    await SecureStorage.deleteAll();
    debugPrint('[AuthService] logout: cleared secure storage');
  }

  static Future<Map<String, dynamic>?> getProfile() async {
    try {
      final res = await http
          .get(
            Uri.parse('$apiBase/profiles/me/'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final role = data['role'] as String?;
        final mfaEnabled = data['mfa_enabled'] == true;
        final email =
            (data['user'] is Map) ? data['user']['email'] as String? : null;

        if (role != null) await SecureStorage.write('role', role);
        if (email != null) await SecureStorage.write('email', email);
        await SecureStorage.write('mfa_enabled', mfaEnabled ? 'true' : 'false');

        debugPrint(
            '[AuthService] getProfile: got profile, role=$role mfaEnabled=$mfaEnabled');
        return data;
      } else if (res.statusCode == 401) {
        final refreshed = await refreshTokens();
        if (refreshed) return getProfile();
        debugPrint('[AuthService] getProfile: unauthorized');
      } else {
        debugPrint(
            '[AuthService] getProfile: status ${res.statusCode} body=${res.body}');
      }
    } catch (e, st) {
      debugPrint('[AuthService] getProfile error: $e\n$st');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> setupMFA() async {
    try {
      final res = await http
          .get(
            Uri.parse('$apiBase/auth/mfa/setup/'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        debugPrint('[AuthService] setupMFA: success keys=${data.keys}');
        return data;
      } else if (res.statusCode == 401) {
        final refreshed = await refreshTokens();
        if (refreshed) return setupMFA();
        debugPrint('[AuthService] setupMFA: unauthorized');
      } else {
        debugPrint(
            '[AuthService] setupMFA: status ${res.statusCode} body=${res.body}');
      }
    } catch (e, st) {
      debugPrint('[AuthService] setupMFA error: $e\n$st');
    }
    return null;
  }

  static Future<Map<String, dynamic>> verifyMFA(String otp) async {
    try {
      final res = await http
          .post(
            Uri.parse('$apiBase/auth/mfa/verify/'),
            headers: await _authHeaders(),
            body: jsonEncode({'otp': otp}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        debugPrint('[AuthService] verifyMFA: response keys=${data.keys}');

        final access =
            (data['access'] as String?) ?? (data['access_token'] as String?);
        final refresh =
            (data['refresh'] as String?) ?? (data['refresh_token'] as String?);
        if (access != null && refresh != null) {
          await SecureStorage.write('access', access);
          await SecureStorage.write('refresh', refresh);
          debugPrint('[AuthService] verifyMFA: saved access & refresh tokens');
        }

        final role = data['role'] as String?;
        if (role != null && role.isNotEmpty) {
          await SecureStorage.write('role', role);
          debugPrint('[AuthService] verifyMFA: saved role=$role');
        }

        await SecureStorage.write('otp_verified', 'true');

        return data..putIfAbsent('success', () => true);
      } else if (res.statusCode == 401) {
        final refreshed = await refreshTokens();
        if (refreshed) return verifyMFA(otp);
        debugPrint('[AuthService] verifyMFA: unauthorized');
      }

      try {
        final err = jsonDecode(res.body);
        return {'success': false, 'error': err};
      } catch (_) {
        return {
          'success': false,
          'error': 'HTTP ${res.statusCode}: ${res.body}'
        };
      }
    } catch (e, st) {
      debugPrint('[AuthService] verifyMFA error: $e\n$st');
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<bool> updateProfile({
    required String nom,
    required String prenom,
    required String email,
    File? photoFile,
  }) async {
    try {
      final uri = Uri.parse('$apiBase/profiles/me/');
      final req = http.MultipartRequest('PUT', uri);
      req.headers.addAll(await _authHeaders(json: false));
      req.fields['nom'] = nom;
      req.fields['prenom'] = prenom;
      req.fields['email'] = email;

      if (photoFile != null && await photoFile.exists()) {
        final mimeType = lookupMimeType(photoFile.path) ?? 'image/jpeg';
        final parts = mimeType.split('/');
        final file = await http.MultipartFile.fromPath(
          'photo',
          photoFile.path,
          contentType: MediaType(parts[0], parts[1]),
        );
        req.files.add(file);
      }

      final streamed = await req.send().timeout(const Duration(seconds: 20));
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200 || resp.statusCode == 204) {
        return true;
      } else if (resp.statusCode == 401) {
        final refreshed = await refreshTokens();
        if (refreshed) {
          return updateProfile(
            nom: nom,
            prenom: prenom,
            email: email,
            photoFile: photoFile,
          );
        }
      }
      debugPrint(
          '[AuthService] updateProfile: status ${resp.statusCode} body=${resp.body}');
      return false;
    } catch (e, st) {
      debugPrint('[AuthService] updateProfile error: $e\n$st');
      return false;
    }
  }
}
