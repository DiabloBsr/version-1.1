// lib/services/multi_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../utils/secure_storage.dart';

class MultiService {
  // Retourne l'hôte adapté (web vs emulator Android)
  static String get _host =>
      kIsWeb ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000';

  // Endpoint par défaut ; adapte si ton backend expose un autre chemin.
  static String get _mfaSetupEndpoint => '$_host/api/v1/auth/mfa/setup/';

  // Récupère la provisioning URI pour la configuration MFA
  // Retourne String? (null en cas d'erreur)
  static Future<String?> setupUrl() async {
    try {
      final token = await SecureStorage.read('access_token');
      if (token == null) throw Exception('Token manquant');

      final res = await http.post(
        Uri.parse(_mfaSetupEndpoint),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
        body: jsonEncode(
            {}), // adapte le corps si ton endpoint attend des paramètres
      );

      // debug
      // ignore: avoid_print
      print('MultiService.setupUrl status=${res.statusCode} body=${res.body}');

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        if (data is Map && data.containsKey('provisioning_uri')) {
          return data['provisioning_uri'] as String?;
        }
        // parfois le backend renvoie directement la chaîne
        if (res.body.isNotEmpty) return res.body;
      }

      // non fatal : retourne null pour que l'UI gère l'erreur
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('MultiService.setupUrl error: $e');
      return null;
    }
  }

  // Exemple générique pour setupFill (adapte l'URL / payload si nécessaire)
  static Future<String?> setupFill(dynamic payload) async {
    try {
      final token = await SecureStorage.read('access_token');
      if (token == null) throw Exception('Token manquant');

      final res = await http.post(
        Uri.parse(_mfaSetupEndpoint),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({'data': payload}),
      );

      // debug
      // ignore: avoid_print
      print('MultiService.setupFill status=${res.statusCode} body=${res.body}');

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        if (data is Map && data.containsKey('provisioning_uri')) {
          return data['provisioning_uri'] as String?;
        }
        return res.body;
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('MultiService.setupFill error: $e');
      return null;
    }
  }
}
