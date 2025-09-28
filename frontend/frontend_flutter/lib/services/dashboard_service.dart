import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import '../utils/secure_storage.dart';
import 'auth_service.dart';

class DashboardService {
  static String get _host {
    if (kIsWeb) return 'http://127.0.0.1:8000'; // Web
    return 'http://10.0.2.2:8000'; // Android Emulator
  }

  static String get baseUrl => '$_host/api/v1/dashboard/summary/';

  /// Fetch dashboard summary.
  /// - Ensures access token is read (await) and present.
  /// - If missing, tries AuthService.refreshTokens() once and retries.
  /// - Throws Exception with meaningful message if no token or if request fails.
  Future<Map<String, dynamic>> fetchDashboardSummary() async {
    // Read access token explicitly at call time (use same key as rest of app)
    String? token = await SecureStorage.read('access');
    if (token == null || token.isEmpty) {
      // Try to refresh once
      final refreshed = await AuthService.refreshTokens();
      if (refreshed) {
        token = await SecureStorage.read('access');
      }
      if (token == null || token.isEmpty) {
        throw Exception('Token manquant. Veuillez vous reconnecter.');
      }
    }

    final uri = Uri.parse(baseUrl);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    debugPrint(
        '[DashboardService] fetchDashboardSummary headers Authorization present: ${headers.containsKey('Authorization')}');

    try {
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      debugPrint(
          '[DashboardService] fetchDashboardSummary status ${response.statusCode}');

      final body = utf8.decode(response.bodyBytes);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        return decoded;
      }

      if (response.statusCode == 401) {
        // Try a refresh once more if possible
        final refreshed = await AuthService.refreshTokens();
        if (refreshed) {
          final newToken = await SecureStorage.read('access');
          if (newToken == null || newToken.isEmpty) {
            throw Exception(
                'Token manquant après refresh. Veuillez vous reconnecter.');
          }
          final retryHeaders = {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $newToken',
          };
          final retryRes = await http
              .get(uri, headers: retryHeaders)
              .timeout(const Duration(seconds: 10));
          debugPrint('[DashboardService] retry status ${retryRes.statusCode}');
          final retryBody = utf8.decode(retryRes.bodyBytes);
          if (retryRes.statusCode == 200) {
            return jsonDecode(retryBody) as Map<String, dynamic>;
          } else {
            throw Exception(
                'Erreur ${retryRes.statusCode}: ${_shorten(retryBody)}');
          }
        } else {
          throw Exception(
              'Unauthorized (401) et refresh échoué. Veuillez vous reconnecter.');
        }
      }

      // Other statuses
      throw Exception('HTTP ${response.statusCode}: ${_shorten(body)}');
    } catch (e) {
      throw Exception('Impossible de contacter le serveur: $e');
    }
  }

  String _shorten(String s, [int max = 300]) {
    if (s.length <= max) return s;
    return s.substring(0, max) + '...';
  }
}
