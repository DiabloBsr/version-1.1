// lib/screens/profile_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../utils/secure_storage.dart';
import 'package:http/http.dart' as http;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  Map<String, dynamic>? _profile;
  Uint8List? _photoBytes;
  String? _email;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _photoBytes = null;
    });

    try {
      _email = await SecureStorage.read('email');
      final p = await AuthService.getProfile();
      if (p != null && mounted) setState(() => _profile = p);

      final access = await SecureStorage.read('access');
      final photoPath = _resolvePhotoPath(_profile);
      if (photoPath != null && access != null) {
        final url = _absolutePhotoUrl(photoPath);
        try {
          final resp = await http.get(
            Uri.parse(url),
            headers: <String, String>{
              'Authorization': 'Bearer $access',
              'Accept': 'application/octet-stream'
            },
          ).timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200 && mounted)
            setState(() => _photoBytes = resp.bodyBytes);
        } catch (_) {
          // ignore and fallback to network image or initials
        }
      }
    } catch (e, st) {
      debugPrint('ProfileScreen _loadProfile error: $e\n$st');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible de charger le profil')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _resolvePhotoPath(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    return profile['photo'] as String? ??
        (profile['user'] is Map ? profile['user']['photo'] as String? : null);
  }

  String _absolutePhotoUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final apiBase = AuthService.apiBase;
    const apiSuffix = '/api/v1';
    String root = apiBase;
    if (apiBase.endsWith(apiSuffix))
      root = apiBase.substring(0, apiBase.length - apiSuffix.length);
    return '$root${path.startsWith('/') ? '' : '/'}$path';
  }

  Widget _avatar(double radius) {
    final first = (_profile?['prenom'] as String?)?.trim() ?? '';
    final last = (_profile?['nom'] as String?)?.trim() ?? '';
    final name = [first, last].where((s) => s.isNotEmpty).join(' ');
    final initials = name.isNotEmpty
        ? name.split(' ').map((s) => s[0]).join().toUpperCase()
        : ((_profile?['user']?['email'] as String?) ?? _email ?? 'U')[0]
            .toUpperCase();

    if (_photoBytes != null) {
      return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(_photoBytes!),
          backgroundColor: Colors.grey.shade100);
    }

    final path = _resolvePhotoPath(_profile);
    if (path != null) {
      return CircleAvatar(
          radius: radius,
          backgroundImage: NetworkImage(_absolutePhotoUrl(path)),
          backgroundColor: Colors.grey.shade100);
    }

    return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.blue.shade700,
        child: Text(initials,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
              onPressed: _loadProfile,
              icon: const Icon(Icons.refresh),
              tooltip: 'Rafraîchir'),
          IconButton(
            onPressed: () async {
              // push edit screen and refresh after return
              await context.push('/profile/edit');
              await _loadProfile();
            },
            icon: const Icon(Icons.edit),
            tooltip: 'Éditer',
          ),
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
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          _avatar(40),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ((_profile?['prenom'] as String?)?.trim() ??
                                            '') +
                                        ' ' +
                                        ((_profile?['nom'] as String?)
                                                ?.trim() ??
                                            ''),
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                      (_profile?['user']?['email']
                                              as String?) ??
                                          _profile?['email'] as String? ??
                                          _email ??
                                          '',
                                      style: TextStyle(
                                          color: theme
                                              .textTheme.bodyMedium?.color
                                              ?.withOpacity(0.9))),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 8, children: [
                                    Chip(
                                        label: Text(
                                            ((_profile?['role'] as String?) ??
                                                    'user')
                                                .toUpperCase()),
                                        backgroundColor: Colors.blue.shade50),
                                  ]),
                                ]),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      _buildDetailTile(
                          'Téléphone', _profile?['telephone'] as String?),
                      _buildDetailTile(
                          'Adresse', _profile?['adresse'] as String?),
                      _buildDetailTile('Date de naissance',
                          _profile?['date_naissance'] as String?),
                      _buildDetailTile('Lieu de naissance',
                          _profile?['lieu_naissance'] as String?),
                      _buildDetailTile('Nombre d\'enfants',
                          _profile?['nombre_enfants']?.toString()),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await context.push('/profile/edit');
                          await _loadProfile();
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Modifier mon profil'),
                      ),
                    ]),
              ),
            ),
    );
  }

  Widget _buildDetailTile(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(value ?? 'Non fourni',
            style: TextStyle(
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withOpacity(0.85))),
      ),
    );
  }
}
