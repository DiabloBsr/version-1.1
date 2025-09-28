import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/secure_storage.dart';

class AuthService {
  static const baseUrl = 'http://127.0.0.1:8000/api/v1/auth';

  /// Connexion avec Djoser JWT
  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/jwt/create/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await SecureStorage.write('access', data['access']);
        await SecureStorage.write('refresh', data['refresh']);
        return {'success': true};
      } else {
        return {'success': false, 'error': res.body};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Inscription (Djoser)
  static Future<Map<String, dynamic>> register(
      Map<String, String> payload) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/users/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (res.statusCode == 201) {
        return {'success': true};
      } else {
        return {'success': false, 'error': res.body};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Récupérer le profil utilisateur connecté
  static Future<Map<String, dynamic>?> getProfile() async {
    final token = await SecureStorage.read('access');
    if (token == null) return null;

    final res = await http.get(
      Uri.parse('$baseUrl/users/me/'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return null;
  }

  /// MFA Setup (renvoie l’URI de provisioning pour QR code)
  static Future<String?> setupMFA() async {
    final token = await SecureStorage.read('access');
    if (token == null) return null;

    final res = await http.post(
      Uri.parse('$baseUrl/mfa/setup/'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['provisioning_uri'];
    }
    return null;
  }

  /// MFA Verify (vérifie le code OTP)
  static Future<Map<String, dynamic>> verifyMFA(String otp) async {
    final token = await SecureStorage.read('access');
    if (token == null) {
      return {'success': false, 'error': 'Token manquant'};
    }

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/mfa/verify/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'otp': otp}),
      );

      if (res.statusCode == 200) {
        return {'success': true};
      } else {
        return {'success': false, 'error': res.body};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Déconnexion (efface les tokens + appelle backend pour blacklister)
  static Future<void> logout() async {
    final refresh = await SecureStorage.read('refresh');
    if (refresh != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/logout/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh': refresh}),
        );
      } catch (_) {
        // on ignore les erreurs réseau ici
      }
    }
    await SecureStorage.delete('access');
    await SecureStorage.delete('refresh');
  }
}
