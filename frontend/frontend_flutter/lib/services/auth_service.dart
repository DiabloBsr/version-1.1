import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import '../utils/secure_storage.dart';

class AuthService {
  // API constants
  static const String apiBase = 'http://127.0.0.1:8000/api/v1';
  static const String _apiBaseRoot = 'http://127.0.0.1:8000';
  static String get baseUrl => _apiBaseRoot;
  static String? appVersion;

  /// Build auth headers. If [json] is true, include Content-Type: application/json.
  static Future<Map<String, String>> _authHeaders(
      {bool json = true, bool acceptJson = true}) async {
    final rawToken = await SecureStorage.read('access');
    final token = rawToken?.trim();
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    if (acceptJson) headers['Accept'] = 'application/json';
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Save token values safely (trimmed)
  static Future<void> _saveAccessRefresh(
      {required String access, String? refresh}) async {
    await SecureStorage.write('access', access.trim());
    if (refresh != null && refresh.trim().isNotEmpty) {
      await SecureStorage.write('refresh', refresh.trim());
    }
  }

  /// Try refresh using refresh token; return true if refreshed successfully.
  static Future<bool> refreshTokens() async {
    final rawRefresh = await SecureStorage.read('refresh');
    final refresh = rawRefresh?.trim();
    if (refresh == null || refresh.isEmpty) {
      debugPrint('[AuthService] refreshTokens: no refresh token');
      return false;
    }

    try {
      final res = await http
          .post(
            Uri.parse('$apiBase/token/refresh/'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
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
          await _saveAccessRefresh(access: access, refresh: refreshNew);
          debugPrint('[AuthService] refreshTokens: success, access updated');
          return true;
        } else {
          debugPrint('[AuthService] refreshTokens: 200 but no access in body');
        }
      } else {
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

  /// Login and persist tokens. Returns map with success or error.
  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      final res = await http
          .post(
            Uri.parse('$apiBase/token/'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
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
          await _saveAccessRefresh(access: access, refresh: refresh);
          debugPrint('[AuthService] login: tokens saved');
          return {'success': true, 'access': access, 'refresh': refresh};
        }
        return {'success': false, 'error': 'Tokens manquants'};
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
      debugPrint('[AuthService] login error: $e\n$st');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Clears local storage tokens and any saved auth details
  static Future<void> logout() async {
    try {
      await SecureStorage.deleteAll();
    } catch (e) {
      try {
        await SecureStorage.delete('access');
        await SecureStorage.delete('refresh');
        await SecureStorage.delete('pending_password');
        await SecureStorage.delete('pending_profile');
        await SecureStorage.delete('email');
        await SecureStorage.delete('role');
        await SecureStorage.delete('mfa_enabled');
        await SecureStorage.delete('otp_verified');
      } catch (inner) {
        debugPrint('SecureStorage fallback delete error: $inner');
      }
    }
    debugPrint('[AuthService] logout: cleared secure storage');
  }

  /// Generic helper: attempts requestFn with current token, on 401 tries refresh once then retries.
  /// requestFn should accept a token and return a Future<http.Response>.
  static Future<http.Response> authenticatedRequest(
      Future<http.Response> Function(String token) requestFn) async {
    String? token = (await SecureStorage.read('access'))?.trim();
    if (token == null || token.isEmpty) {
      throw Exception('No access token');
    }

    var resp = await requestFn(token);
    if (resp.statusCode != 401) return resp;

    final refreshed = await refreshTokens();
    if (!refreshed) return resp;

    token = (await SecureStorage.read('access'))?.trim();
    if (token == null || token.isEmpty)
      throw Exception('No access token after refresh');

    resp = await requestFn(token);
    return resp;
  }

  /// Returns profile Map or null. Performs refresh on 401.
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
        final email = (data['user'] is Map)
            ? data['user']['email'] as String?
            : data['email'] as String?;

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

  /// Verify MFA OTP. Returns map with success flag or error detail.
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

        // Persist tokens if present
        final access =
            (data['access'] as String?) ?? (data['access_token'] as String?);
        final refresh =
            (data['refresh'] as String?) ?? (data['refresh_token'] as String?);
        if (access != null && refresh != null) {
          await _saveAccessRefresh(access: access, refresh: refresh);
          debugPrint('[AuthService] verifyMFA: saved access & refresh tokens');
        }

        // Persist role if provided
        final role = data['role'] as String?;
        if (role != null && role.isNotEmpty) {
          await SecureStorage.write('role', role);
          debugPrint('[AuthService] verifyMFA: saved role=$role');
        }

        // Mark OTP verified locally
        await SecureStorage.write('otp_verified', 'true');

        // Return data augmented with success flag
        final Map<String, dynamic> result = Map<String, dynamic>.from(data);
        result['success'] = true;
        return result;
      } else if (res.statusCode == 401) {
        final refreshed = await refreshTokens();
        if (refreshed) return verifyMFA(otp);
        debugPrint('[AuthService] verifyMFA: unauthorized');
      }

      // Try decode error body for caller
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

  // --- multipart helpers (mobile + web) ---

  /// Send multipart with optional File (mobile). Default photo field is 'photo'.
  static Future<Map<String, dynamic>> updateProfileRaw({
    required String url,
    required String accessToken,
    required Map<String, String> fields,
    File? photoFile,
    String photoField = 'photo',
    String method =
        'PATCH', // 'PATCH' by default; change to 'PUT' or 'POST' if needed
  }) async {
    try {
      final uri = Uri.parse(url);
      final request = http.MultipartRequest(method, uri);
      request.headers['Authorization'] = 'Bearer $accessToken';
      request.headers['Accept'] = 'application/json';

      // add text fields
      fields.forEach((k, v) => request.fields[k] = v);

      // add file if present
      if (photoFile != null && await photoFile.exists()) {
        final mimeType =
            lookupMimeType(photoFile.path) ?? 'application/octet-stream';
        final parts = mimeType.split('/');
        final stream = http.ByteStream(photoFile.openRead());
        final length = await photoFile.length();
        final multipartFile = http.MultipartFile(
          photoField,
          stream,
          length,
          filename: p.basename(photoFile.path),
          contentType: MediaType(parts[0], parts[1]),
        );
        request.files.add(multipartFile);
      }

      debugPrint(
          '[AuthService] updateProfileRaw -> method=$method url=$url fields=${fields.keys} files=${request.files.map((f) => f.filename).toList()}');
      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamed);
      debugPrint(
          '[AuthService] updateProfileRaw: ${resp.statusCode} ${resp.body}');
      final body =
          resp.body.isNotEmpty ? jsonDecode(resp.body) : <String, dynamic>{};
      return {'status': resp.statusCode, 'body': body};
    } catch (e, st) {
      debugPrint('[AuthService] updateProfileRaw error: $e\n$st');
      return {'status': 0, 'error': e.toString()};
    }
  }

  /// Send multipart by attaching bytes (web-friendly). Default photo field is 'photo'.
  static Future<Map<String, dynamic>> updateProfileRawFromBytes({
    required String url,
    required String accessToken,
    required Map<String, String> fields,
    required Uint8List bytes,
    required String filename,
    String photoField = 'photo',
    String method = 'PATCH',
  }) async {
    try {
      final uri = Uri.parse(url);
      final request = http.MultipartRequest(method, uri);
      request.headers['Authorization'] = 'Bearer $accessToken';
      request.headers['Accept'] = 'application/json';
      fields.forEach((k, v) => request.fields[k] = v);

      final mimeType = lookupMimeType(filename) ?? 'application/octet-stream';
      final parts = mimeType.split('/');
      final multipartFile = http.MultipartFile.fromBytes(
        photoField,
        bytes,
        filename: filename,
        contentType: MediaType(parts[0], parts[1]),
      );
      request.files.add(multipartFile);

      debugPrint(
          '[AuthService] updateProfileRawFromBytes -> method=$method url=$url fields=${fields.keys} file=$filename mime=$mimeType');
      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamed);
      debugPrint(
          '[AuthService] updateProfileRawFromBytes: ${resp.statusCode} ${resp.body}');
      final body =
          resp.body.isNotEmpty ? jsonDecode(resp.body) : <String, dynamic>{};
      return {'status': resp.statusCode, 'body': body};
    } catch (e, st) {
      debugPrint('[AuthService] updateProfileRawFromBytes error: $e\n$st');
      return {'status': 0, 'error': e.toString()};
    }
  }

  /// Wrapper used by the UI. Returns true on success.
  static Future<bool> updateProfile({
    required String nom,
    required String prenom,
    required String email,
    File? photoFile,
    Map<String, String>? extraFields,
    String photoField = 'photo',
    String method = 'PATCH',
  }) async {
    final access = (await SecureStorage.read('access'))?.trim();
    if (access == null || access.isEmpty) {
      debugPrint('[AuthService] updateProfile: no access token');
      return false;
    }

    final url = '$apiBase/profiles/me/';
    final fields = <String, String>{
      'nom': nom,
      'prenom': prenom,
      'email': email,
      if (extraFields != null) ...extraFields,
    };

    final result = await updateProfileRaw(
        url: url,
        accessToken: access,
        fields: fields,
        photoFile: photoFile,
        photoField: photoField,
        method: method);
    final status = result['status'] as int? ?? 0;

    if (status >= 200 && status < 300) {
      try {
        final profile = await getProfile();
        if (profile != null)
          debugPrint('[AuthService] updateProfile: profile refreshed');
      } catch (_) {}
      return true;
    }

    debugPrint('[AuthService] updateProfile failed: $result');
    if (status == 401) {
      final refreshed = await refreshTokens();
      if (refreshed) {
        final retry = await updateProfileRaw(
            url: url,
            accessToken: (await SecureStorage.read('access'))?.trim() ?? '',
            fields: fields,
            photoFile: photoFile,
            photoField: photoField,
            method: method);
        final retryStatus = retry['status'] as int? ?? 0;
        debugPrint('[AuthService] updateProfile retry: $retry');
        return retryStatus >= 200 && retryStatus < 300;
      }
    }
    return false;
  }

  /// Web-friendly wrapper: sends bytes + filename.
  static Future<bool> updateProfileWithBytes({
    required String nom,
    required String prenom,
    required String email,
    required Uint8List? photoBytes,
    String? filename,
    Map<String, String>? extraFields,
    String photoField = 'photo',
    String method = 'PATCH',
  }) async {
    final access = (await SecureStorage.read('access'))?.trim();
    if (access == null || access.isEmpty) {
      debugPrint('[AuthService] updateProfileWithBytes: no access token');
      return false;
    }

    final url = '$apiBase/profiles/me/';
    final fields = <String, String>{
      'nom': nom,
      'prenom': prenom,
      'email': email,
      if (extraFields != null) ...extraFields,
    };

    if (photoBytes != null && filename != null && filename.isNotEmpty) {
      final res = await updateProfileRawFromBytes(
        url: url,
        accessToken: access,
        fields: fields,
        bytes: photoBytes,
        filename: filename,
        photoField: photoField,
        method: method,
      );
      final status = res['status'] as int? ?? 0;
      if (status >= 200 && status < 300) {
        try {
          final profile = await getProfile();
          if (profile != null)
            debugPrint(
                '[AuthService] updateProfileWithBytes: profile refreshed');
        } catch (_) {}
        return true;
      }
      debugPrint('[AuthService] updateProfileWithBytes failed: $res');
      if (status == 401) {
        final refreshed = await refreshTokens();
        if (refreshed) {
          final access2 = (await SecureStorage.read('access'))?.trim() ?? '';
          final retry = await updateProfileRawFromBytes(
            url: url,
            accessToken: access2,
            fields: fields,
            bytes: photoBytes,
            filename: filename,
            photoField: photoField,
            method: method,
          );
          final retryStatus = retry['status'] as int? ?? 0;
          debugPrint('[AuthService] updateProfileWithBytes retry: $retry');
          return retryStatus >= 200 && retryStatus < 300;
        }
      }
      return false;
    } else {
      return updateProfile(
        nom: nom,
        prenom: prenom,
        email: email,
        photoFile: null,
        extraFields: extraFields,
        photoField: photoField,
        method: method,
      );
    }
  }

  /// Fetch protected bytes (used for avatar preview).
  static Future<Uint8List?> fetchBytes(String url, String? accessToken) async {
    try {
      final headers = <String, String>{'Accept': 'application/octet-stream'};
      if (accessToken != null && accessToken.isNotEmpty)
        headers['Authorization'] = 'Bearer $accessToken';

      final resp = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) return resp.bodyBytes;

      if (resp.statusCode == 401) {
        final refreshed = await refreshTokens();
        if (refreshed) {
          final newToken = (await SecureStorage.read('access'))?.trim();
          final resp2 = await http.get(Uri.parse(url), headers: {
            'Accept': 'application/octet-stream',
            if (newToken != null && newToken.isNotEmpty)
              'Authorization': 'Bearer $newToken'
          }).timeout(const Duration(seconds: 12));
          if (resp2.statusCode == 200) return resp2.bodyBytes;
        }
      }
      debugPrint('[AuthService] fetchBytes failed: ${resp.statusCode}');
    } catch (e, st) {
      debugPrint('[AuthService] fetchBytes error: $e\n$st');
    }
    return null;
  }

  /// POST a user activity to the server.
  /// activity must contain at least: text (String), type (optional), timestamp (optional), meta (optional).
  /// Returns true if persisted (201 created) or false otherwise.
  static Future<bool> postActivity(Map<String, dynamic> activity) async {
    final token = (await SecureStorage.read('access'))?.trim();
    if (token == null || token.isEmpty) return false;
    try {
      final resp = await http
          .post(Uri.parse('$apiBase/activities/'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
                'Accept': 'application/json'
              },
              body: jsonEncode(activity))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 201 || resp.statusCode == 200) {
        debugPrint('[AuthService] postActivity: success ${resp.statusCode}');
        return true;
      } else if (resp.statusCode == 401) {
        final refreshed = await refreshTokens();
        if (refreshed) return postActivity(activity);
      } else {
        debugPrint(
            '[AuthService] postActivity failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e, st) {
      debugPrint('[AuthService] postActivity error: $e\n$st');
    }
    return false;
  }

  /// POST a batch of activities to the server.
  /// Payload: { "activities": [ {...}, ... ] }
  /// Returns decoded server response map or null on failure.
  static Future<Map<String, dynamic>?> postActivitiesBatch(
      List<Map<String, dynamic>> activities) async {
    final token = (await SecureStorage.read('access'))?.trim();
    if (token == null || token.isEmpty) return null;
    try {
      final resp = await http
          .post(
            Uri.parse('$apiBase/activities/batch/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: jsonEncode({'activities': activities}),
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } else if (resp.statusCode == 401) {
        final refreshed = await refreshTokens();
        if (refreshed) return postActivitiesBatch(activities);
      } else {
        debugPrint(
            '[AuthService] postActivitiesBatch failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e, st) {
      debugPrint('[AuthService] postActivitiesBatch error: $e\n$st');
    }
    return null;
  }

  /// Fetch activities for current user. Uses /activities/ endpoint with optional query params.
  /// Returns list of maps (may be empty).
  static Future<List<Map<String, dynamic>>> getActivities(
      {int limit = 100, String? type, int? page}) async {
    final token = (await SecureStorage.read('access'))?.trim();
    if (token == null || token.isEmpty) return [];
    try {
      final query = <String, String>{'limit': '$limit'};
      if (type != null) query['type'] = type;
      if (page != null) query['page'] = '$page';
      final uri =
          Uri.parse('$apiBase/activities/').replace(queryParameters: query);
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is List) {
          return body.map<Map<String, dynamic>>((e) {
            if (e is Map) return Map<String, dynamic>.from(e);
            return {'text': e.toString()};
          }).toList();
        }
        // support paginated or envelope responses {results: [...]}
        if (body is Map && body['results'] is List) {
          return (body['results'] as List).map<Map<String, dynamic>>((e) {
            if (e is Map) return Map<String, dynamic>.from(e);
            return {'text': e.toString()};
          }).toList();
        }
      } else if (resp.statusCode == 401) {
        final refreshed = await refreshTokens();
        if (refreshed)
          return getActivities(limit: limit, type: type, page: page);
        debugPrint('[AuthService] getActivities: unauthorized');
      } else {
        debugPrint(
            '[AuthService] getActivities: status ${resp.statusCode} body=${resp.body}');
      }
    } catch (e, st) {
      debugPrint('[AuthService] getActivities error: $e\n$st');
    }
    return [];
  }
}
