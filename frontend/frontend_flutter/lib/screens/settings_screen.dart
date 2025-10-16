// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../utils/secure_storage.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _darkMode = false;
  String? _email;
  String? _role;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      _email = await SecureStorage.read('email');
      _role = await SecureStorage.read('role');
      final theme = await SecureStorage.read('dark_mode');
      _darkMode = theme == 'true';
    } catch (e) {
      debugPrint('Settings load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleDarkMode(bool value) async {
    setState(() => _darkMode = value);
    try {
      await SecureStorage.write('dark_mode', value ? 'true' : 'false');
    } catch (e) {
      debugPrint('Failed saving theme: $e');
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer'),
        content:
            const Text('Supprimer les données locales de l\'application ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await SecureStorage.delete('access');
      await SecureStorage.delete('refresh');
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Données locales supprimées')));
    } catch (e) {
      debugPrint('Clear cache error: $e');
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _signOut() async {
    try {
      await AuthService.logout();
    } catch (e) {
      debugPrint('Logout error: $e');
    } finally {
      try {
        await SecureStorage.delete('access');
        await SecureStorage.delete('refresh');
        await SecureStorage.delete('email');
        await SecureStorage.delete('role');
      } catch (_) {}
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        actions: [
          IconButton(onPressed: _loadSettings, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(_email ?? 'Non connecté'),
                        subtitle: Text('Rôle: ${_role ?? "—"}'),
                      ),
                      const Divider(),
                      SwitchListTile(
                        value: _darkMode,
                        onChanged: _toggleDarkMode,
                        title: const Text('Mode sombre'),
                        secondary: const Icon(Icons.brightness_6),
                      ),
                      ListTile(
                        leading: const Icon(Icons.payment),
                        title: const Text('Comptes bancaires'),
                        onTap: () => context.go('/profile-extra'),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Supprimer les données locales'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700),
                        onPressed: _clearCache,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('Se déconnecter'),
                        onPressed: _signOut,
                      ),
                    ]),
              ),
            ),
    );
  }
}
