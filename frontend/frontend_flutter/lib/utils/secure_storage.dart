import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorage {
  // Instance unique de FlutterSecureStorage
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true, // ✅ stockage chiffré sur Android
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock, // ✅ iOS Keychain
    ),
  );

  /// Écrit une valeur sécurisée
  static Future<void> write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _secure.write(key: key, value: value);
    }
  }

  /// Lit une valeur sécurisée
  static Future<String?> read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } else {
      return await _secure.read(key: key);
    }
  }

  /// Supprime une clé spécifique
  static Future<void> delete(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } else {
      await _secure.delete(key: key);
    }
  }

  /// Supprime toutes les clés
  static Future<void> deleteAll() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } else {
      await _secure.deleteAll();
    }
  }
}
