// lib/services/user_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File, SocketException;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../utils/secure_storage.dart';

class EndpointNotFoundException implements Exception {
  final String message;
  EndpointNotFoundException(
      [this.message = 'Existence-check endpoint not found on server']);
  @override
  String toString() => 'EndpointNotFoundException: $message';
}

class EndpointAuthRequiredException implements Exception {
  final String message;
  EndpointAuthRequiredException(
      [this.message = 'Existence-check endpoint requires authentication']);
  @override
  String toString() => 'EndpointAuthRequiredException: $message';
}

class UserService {
  static final String baseUrl =
      const String.fromEnvironment('API_BASE_URL', defaultValue: '') != ''
          ? const String.fromEnvironment('API_BASE_URL')
          : (kIsWeb
              ? 'http://localhost:8000/api/v1'
              : 'http://10.0.2.2:8000/api/v1');

  static const Duration _singleTimeout = Duration(seconds: 8);
  static const int _maxAttempts = 3;
  static const Duration _initialBackoff = Duration(milliseconds: 300);

  static const List<String> _existencePaths = [
    '/users/exists',
    '/auth/users/exists',
    '/profiles/exists',
    '/profiles/exists/',
  ];

  static Future<http.Response> _getWithRetry(
      Uri uri, Map<String, String> headers) async {
    Duration backoff = _initialBackoff;
    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        debugPrint(
            '[UserService] GET attempt $attempt -> $uri (headers: ${headers.keys.toList()})');
        final resp =
            await http.get(uri, headers: headers).timeout(_singleTimeout);
        debugPrint(
            '[UserService] GET $uri status=${resp.statusCode} body=${resp.body}');
        return resp;
      } on TimeoutException catch (e) {
        debugPrint('[UserService] GET timeout attempt $attempt for $uri: $e');
        if (attempt == _maxAttempts) rethrow;
      } on SocketException catch (e) {
        debugPrint(
            '[UserService] GET socket exception attempt $attempt for $uri: $e');
        if (attempt == _maxAttempts) rethrow;
      } catch (e, st) {
        debugPrint(
            '[UserService] GET unexpected attempt $attempt for $uri: $e\n$st');
        if (attempt == _maxAttempts) rethrow;
      }
      await Future.delayed(backoff);
      backoff *= 2;
    }
    throw Exception('GET with retry failed for $uri');
  }

  // Try candidate endpoints, first anonymously (no Authorization), then with token if anonymous tries all return 404/401.
  static Future<bool> _tryExistenceEndpoints(Map<String, String> query) async {
    bool saw401 = false;
    for (final path in _existencePaths) {
      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);

      // 1) try anonymous (no Authorization)
      try {
        final headersAnon = <String, String>{'Accept': 'application/json'};
        final respAnon = await _getWithRetry(uri, headersAnon);
        if (respAnon.statusCode == 404) {
          debugPrint('[UserService] $uri -> 404 (anon), trying next');
          continue;
        }
        if (respAnon.statusCode == 401) {
          debugPrint('[UserService] $uri -> 401 (anon) : auth required');
          saw401 = true;
          // don't continue to parse anonymous body; we'll try authenticated later
          continue;
        }
        if (respAnon.statusCode == 200) {
          // parse result
          try {
            final body = json.decode(respAnon.body);
            if (body is Map && body.containsKey('exists'))
              return body['exists'] == true;
            if (body is bool) return body;
          } catch (e) {
            debugPrint(
                '[UserService] parse error anon for $uri : $e body=${respAnon.body}');
          }
          final cleaned = respAnon.body.trim().toLowerCase();
          if (cleaned == 'true') return true;
          if (cleaned == 'false') return false;
          throw Exception(
              'Unexpected response body for existence check: ${respAnon.body}');
        }
        // any other status: surface error
        throw Exception(
            'Existence check returned status ${respAnon.statusCode}: ${respAnon.body}');
      } on TimeoutException {
        rethrow;
      }
    } // end anon attempts

    // If we observed 401 on any anon attempt, try authenticated variant for same endpoints
    if (saw401) {
      final token = await SecureStorage.read('access_token');
      final headersAuth = <String, String>{
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      for (final path in _existencePaths) {
        final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
        try {
          final resp = await _getWithRetry(uri, headersAuth);
          if (resp.statusCode == 404) {
            debugPrint('[UserService] auth try $uri -> 404, trying next');
            continue;
          }
          if (resp.statusCode == 401) {
            // endpoint exists but server requires credentials we don't have/are invalid
            throw EndpointAuthRequiredException(
                'Endpoint $uri requires authentication');
          }
          if (resp.statusCode == 200) {
            try {
              final body = json.decode(resp.body);
              if (body is Map && body.containsKey('exists'))
                return body['exists'] == true;
              if (body is bool) return body;
            } catch (e) {
              debugPrint(
                  '[UserService] parse error auth for $uri : $e body=${resp.body}');
            }
            final cleaned = resp.body.trim().toLowerCase();
            if (cleaned == 'true') return true;
            if (cleaned == 'false') return false;
            throw Exception(
                'Unexpected response body for existence check: ${resp.body}');
          }
          throw Exception(
              'Existence check returned status ${resp.statusCode}: ${resp.body}');
        } on TimeoutException {
          rethrow;
        }
      }
    }

    // no endpoint matched (all 404)
    throw EndpointNotFoundException(
        'No existence-check endpoint found under $baseUrl (checked ${_existencePaths.join(", ")})');
  }

  static Future<bool> usernameExists(String username) async {
    if (username.trim().isEmpty) return false;
    return await _tryExistenceEndpoints({'username': username});
  }

  static Future<bool> emailExists(String email) async {
    if (email.trim().isEmpty) return false;
    return await _tryExistenceEndpoints({'email': email});
  }

  /// Récupère le profil de l’utilisateur connecté
  static Future<Map<String, dynamic>> getProfile() async {
    final token = await SecureStorage.read('access_token');
    final res = await http.get(
      Uri.parse('$baseUrl/profiles/me/'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_singleTimeout);
    if (res.statusCode != 200) {
      throw Exception('Erreur getProfile: ${res.statusCode} - ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Met à jour le profil (nom, prénom, email, téléphone, etc.)
  static Future<Map<String, dynamic>> updateProfile(
      Map<String, dynamic> data) async {
    final token = await SecureStorage.read('access_token');
    final res = await http
        .patch(
          Uri.parse('$baseUrl/profiles/me/update/'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(data),
        )
        .timeout(_singleTimeout);
    if (res.statusCode != 200) {
      throw Exception('Erreur updateProfile: ${res.statusCode} - ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Upload de la photo de profil (mobile)
  static Future<void> uploadProfilePhoto(File imageFile) async {
    final token = await SecureStorage.read('access_token');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/profiles/me/upload-photo/'),
    );
    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(await http.MultipartFile.fromPath(
      'photo',
      imageFile.path,
      contentType: MediaType('image', 'jpeg'),
    ));

    final streamed = await request.send().timeout(_singleTimeout);
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw Exception('Erreur upload photo: ${streamed.statusCode} - $body');
    }
  }

  /// Upload de la photo de profil (web)
  static Future<void> uploadProfilePhotoWeb(Uint8List bytes) async {
    final token = await SecureStorage.read('access_token');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/profiles/me/upload-photo/'),
    );
    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(http.MultipartFile.fromBytes(
      'photo',
      bytes,
      filename: 'profile.png',
      contentType: MediaType('image', 'png'),
    ));

    final streamed = await request.send().timeout(_singleTimeout);
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw Exception(
          'Erreur upload photo (web): ${streamed.statusCode} - $body');
    }
  }

  /// Changer le mot de passe
  static Future<void> changePassword(String oldPwd, String newPwd) async {
    final token = await SecureStorage.read('access_token');
    final res = await http
        .post(
          Uri.parse('$baseUrl/profiles/change-password/'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'old_password': oldPwd, 'new_password': newPwd}),
        )
        .timeout(_singleTimeout);
    if (res.statusCode != 200) {
      throw Exception('Erreur changePassword: ${res.statusCode} - ${res.body}');
    }
  }

  /// Activer/désactiver MFA (OTP)
  static Future<Map<String, dynamic>> setMFA(
      {required bool enabled, String? method}) async {
    final token = await SecureStorage.read('access_token');
    final res = await http
        .patch(
          Uri.parse('$baseUrl/profiles/me/mfa/'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'is_mfa_enabled': enabled,
            if (method != null) 'preferred_2fa': method
          }),
        )
        .timeout(_singleTimeout);
    if (res.statusCode != 200) {
      throw Exception('Erreur setMFA: ${res.statusCode} - ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
