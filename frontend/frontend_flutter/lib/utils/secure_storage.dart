// lib/utils/secure_storage.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorage {
  // Instance unique de FlutterSecureStorage
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // Clés courantes utilisées par l'app (fallback pour deleteAll)
  static const List<String> _knownKeys = <String>[
    'access',
    'refresh',
    'pending_password',
    'pending_profile',
    'email',
    'role',
    'dark_mode',
  ];

  /// Écrit une valeur sécurisée. Trim la valeur avant stockage.
  static Future<void> write(String key, String value) async {
    final v = value.trim();
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, v);
      } else {
        await _secure.write(key: key, value: v);
      }
    } catch (e, st) {
      debugPrint('[SecureStorage] write error for $key: $e\n$st');
      rethrow;
    }
  }

  /// Lit une valeur sécurisée. Retourne la valeur trimée ou null.
  static Future<String?> read(String key) async {
    try {
      String? v;
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        v = prefs.getString(key);
      } else {
        v = await _secure.read(key: key);
      }
      return v?.trim();
    } catch (e, st) {
      debugPrint('[SecureStorage] read error for $key: $e\n$st');
      return null;
    }
  }

  /// Lit toutes les paires clé/valeur (utile pour debug ou migration).
  /// Sur mobile, utilise readAll() de flutter_secure_storage; sur web, SharedPreferences.
  static Future<Map<String, String>> readAll() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getKeys().fold<Map<String, String>>({}, (acc, k) {
          final v = prefs.getString(k);
          if (v != null) acc[k] = v;
          return acc;
        });
      } else {
        return await _secure.readAll();
      }
    } catch (e, st) {
      debugPrint('[SecureStorage] readAll error: $e\n$st');
      return <String, String>{};
    }
  }

  /// Écrit la valeur seulement si la clé est absente ou vide.
  static Future<bool> writeIfAbsent(String key, String value) async {
    final existing = await read(key);
    if (existing != null && existing.isNotEmpty) return false;
    await write(key, value);
    return true;
  }

  /// Supprime une clé spécifique
  static Future<void> delete(String key) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } else {
        await _secure.delete(key: key);
      }
    } catch (e, st) {
      debugPrint('[SecureStorage] delete error for $key: $e\n$st');
    }
  }

  /// Supprime toutes les clés. Tente deleteAll puis retombe sur la suppression
  /// clé-par-clé pour les clés connues si nécessaire.
  static Future<void> deleteAll() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        return;
      }

      // Try native deleteAll first
      await _secure.deleteAll();
    } catch (e, st) {
      debugPrint('[SecureStorage] deleteAll native failed: $e\n$st');
      // Fallback: remove known keys one-by-one
      try {
        for (final k in _knownKeys) {
          await _secure.delete(key: k);
        }
      } catch (inner, st2) {
        debugPrint('[SecureStorage] deleteAll fallback failed: $inner\n$st2');
      }
    }
  }

  /// Migration helper: move keys from SharedPreferences to secure storage (mobile only).
  /// Returns the list of migrated keys.
  static Future<List<String>> migrateFromSharedPreferences(
      {List<String>? keysToMigrate}) async {
    final migrated = <String>[];
    if (kIsWeb) return migrated;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = keysToMigrate ?? prefs.getKeys().toList();
      for (final k in keys) {
        final v = prefs.getString(k);
        if (v != null && v.isNotEmpty) {
          await _secure.write(key: k, value: v);
          migrated.add(k);
        }
      }
    } catch (e, st) {
      debugPrint('[SecureStorage] migrateFromSharedPreferences error: $e\n$st');
    }
    return migrated;
  }
}
