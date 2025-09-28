import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../utils/secure_storage.dart';

class UserService {
  // ⚠️ Adapte l’URL selon ton environnement (émulateur Android = 10.0.2.2, web = localhost)
  static const String baseUrl = "http://10.0.2.2:8000/api/v1";

  /// Récupère le profil de l’utilisateur connecté
  static Future<Map<String, dynamic>> getProfile() async {
    final token = await SecureStorage.read("access_token");
    final res = await http.get(
      Uri.parse("$baseUrl/profiles/me/"),
      headers: {"Authorization": "Bearer $token"},
    );
    if (res.statusCode != 200) {
      throw Exception("Erreur getProfile: ${res.statusCode} - ${res.body}");
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Met à jour le profil (nom, prénom, email, téléphone, etc.)
  static Future<Map<String, dynamic>> updateProfile(
      Map<String, dynamic> data) async {
    final token = await SecureStorage.read("access_token");
    final res = await http.patch(
      Uri.parse("$baseUrl/profiles/me/update/"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode(data),
    );
    if (res.statusCode != 200) {
      throw Exception("Erreur updateProfile: ${res.statusCode} - ${res.body}");
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Upload de la photo de profil (mobile)
  static Future<void> uploadProfilePhoto(File imageFile) async {
    final token = await SecureStorage.read("access_token");
    final request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/profiles/me/upload-photo/"),
    );
    request.headers["Authorization"] = "Bearer $token";

    request.files.add(await http.MultipartFile.fromPath(
      "photo",
      imageFile.path,
      contentType: MediaType("image", "jpeg"), // ou png
    ));

    final response = await request.send();
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception("Erreur upload photo: ${response.statusCode} - $body");
    }
  }

  /// Upload de la photo de profil (web)
  static Future<void> uploadProfilePhotoWeb(Uint8List bytes) async {
    final token = await SecureStorage.read("access_token");
    final request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/profiles/me/upload-photo/"),
    );
    request.headers["Authorization"] = "Bearer $token";

    request.files.add(http.MultipartFile.fromBytes(
      "photo",
      bytes,
      filename: "profile.png",
      contentType: MediaType("image", "png"),
    ));

    final response = await request.send();
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception(
          "Erreur upload photo (web): ${response.statusCode} - $body");
    }
  }

  /// Changer le mot de passe
  static Future<void> changePassword(String oldPwd, String newPwd) async {
    final token = await SecureStorage.read("access_token");
    final res = await http.post(
      Uri.parse("$baseUrl/profiles/change-password/"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "old_password": oldPwd,
        "new_password": newPwd,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception("Erreur changePassword: ${res.statusCode} - ${res.body}");
    }
  }

  /// Activer/désactiver MFA (OTP)
  static Future<Map<String, dynamic>> setMFA(
      {required bool enabled, String? method}) async {
    final token = await SecureStorage.read("access_token");
    final res = await http.patch(
      Uri.parse("$baseUrl/profiles/me/mfa/"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "is_mfa_enabled": enabled,
        if (method != null) "preferred_2fa": method,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception("Erreur setMFA: ${res.statusCode} - ${res.body}");
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
