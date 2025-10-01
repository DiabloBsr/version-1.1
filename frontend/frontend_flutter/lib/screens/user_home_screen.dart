// lib/screens/user_home_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/secure_storage.dart';
import '../services/auth_service.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({Key? key}) : super(key: key);

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _loggingOut = false;
  Map<String, dynamic>? _profile;
  String? _email;
  Uint8List? _photoBytes;
  late final AnimationController _fadeController;

  // Local in-memory activities loaded from secure storage and runtime captures
  // Each local entry shape: { text, timestamp, type, meta?, synced: bool, id?:String }
  List<Map<String, dynamic>> _localActivities = [];

  // Server-side activities loaded via AuthService.getActivities
  List<Map<String, dynamic>> _serverActivities = [];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();
    _loadAll();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadAll({Map<String, dynamic>? previousProfile}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _photoBytes = null;
    });

    try {
      // 1) reconcile stored local activities: try to post unsynced entries and update local storage
      await _reconcileStoredLocalActivities();

      // 2) load profile
      final profile = await AuthService.getProfile();
      if (profile == null) {
        if (mounted) context.go('/login');
        return;
      }
      if (mounted) setState(() => _profile = profile);
      _email = (profile['user'] is Map)
          ? profile['user']['email'] as String?
          : profile['email'] as String?;

      // 3) if previousProfile provided, compute diff and persist/show
      if (previousProfile != null) {
        final changes = _computeProfileDiff(previousProfile, profile);
        if (changes.isNotEmpty) {
          final now = DateTime.now().toIso8601String();
          final entries = changes
              .map((c) => {
                    'text': 'Profil mis à jour: $c',
                    'timestamp': now,
                    'type': 'profile_change',
                    'meta': {'change': c},
                    'synced': false
                  })
              .toList();

          // try posting, mark synced true on success
          final List<Map<String, dynamic>> remain = [];
          for (final e in entries) {
            final posted = await AuthService.postActivity(e);
            if (posted) {
              e['synced'] = true;
            } else {
              e['synced'] = false;
              remain.add(e);
            }
          }

          // store remaining failures locally (persist)
          if (remain.isNotEmpty) await _storeLocalActivities(remain);

          // always show new entries immediately (some may be synced)
          setState(() => _localActivities = [...entries, ..._localActivities]);
        }
      }

      // 4) load server activities
      _serverActivities = await AuthService.getActivities(limit: 100);

      // 5) load avatar bytes if available
      final photoPath = _resolvePhotoPath(_profile);
      if (photoPath != null && photoPath.isNotEmpty) {
        final access = await SecureStorage.read('access');
        final url = _absolutePhotoUrl(photoPath);
        final bytes = await AuthService.fetchBytes(url, access);
        if (bytes != null && mounted) setState(() => _photoBytes = bytes);
      }
    } catch (e, st) {
      debugPrint('[UserHome] _loadAll error: $e\n$st');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reconcileStoredLocalActivities() async {
    try {
      final raw = await SecureStorage.read('local_activities');
      if (raw == null) return;
      final parsedRaw = jsonDecode(raw) as List;
      if (parsedRaw.isEmpty) {
        await SecureStorage.delete('local_activities');
        return;
      }

      // Normalize and ensure 'synced' field exists
      final entries = parsedRaw.map<Map<String, dynamic>>((e) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          m['synced'] = m['synced'] == true;
          return m;
        }
        return {
          'text': e.toString(),
          'timestamp': '',
          'type': null,
          'synced': false
        };
      }).toList();

      final List<Map<String, dynamic>> failures = [];
      for (final e in entries) {
        // skip already-synced entries (defensive)
        if (e['synced'] == true) continue;
        try {
          final posted = await AuthService.postActivity(e);
          if (!posted) failures.add(e);
        } catch (err) {
          debugPrint('[UserHome] reconcile postActivity error: $err');
          failures.add(e);
        }
      }

      // Persist failures only
      if (failures.isEmpty) {
        await SecureStorage.delete('local_activities');
      } else {
        await SecureStorage.write('local_activities', jsonEncode(failures));
      }

      // update in-memory local activities to show remaining unsynced ones first
      final unsynced = failures;
      setState(() => _localActivities = [...unsynced, ..._localActivities]);
    } catch (e, st) {
      debugPrint('[UserHome] _reconcileStoredLocalActivities error: $e\n$st');
    }
  }

  Future<void> _storeLocalActivities(List<Map<String, dynamic>> entries) async {
    try {
      // ensure entries have synced flag
      final normalized = entries.map((e) {
        final m = Map<String, dynamic>.from(e);
        m['synced'] = m['synced'] == true;
        return m;
      }).toList();

      final raw = await SecureStorage.read('local_activities');
      List existing = raw != null ? jsonDecode(raw) as List : [];
      existing = [...normalized, ...existing];
      await SecureStorage.write('local_activities', jsonEncode(existing));
      debugPrint(
          '[UserHome] stored local activities (fallback): ${normalized.length}');
    } catch (e) {
      debugPrint('[UserHome] failed to store local activities: $e');
    }
  }

  String? _resolvePhotoPath(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    return profile['photo'] as String? ??
        (profile['user'] is Map ? profile['user']['photo'] as String? : null);
  }

  String _absolutePhotoUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final trimmed = path.startsWith('/') ? path : '/$path';
    final apiBaseRoot = AuthService.baseUrl;
    return '$apiBaseRoot$trimmed';
  }

  Future<void> _logout(BuildContext context) async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await AuthService.logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Déconnecté')));
      context.go('/login');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur lors de la déconnexion: $e')));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Widget _buildAvatar(double radius) {
    final first = (_profile?['prenom'] as String?)?.trim() ?? '';
    final last = (_profile?['nom'] as String?)?.trim() ?? '';
    final name = [first, last].where((s) => s.isNotEmpty).join(' ');
    final initials = name.isNotEmpty
        ? name.split(' ').map((s) => s[0]).join().toUpperCase()
        : ((_profile?['user']?['email'] as String?) ?? _email ?? 'U')[0]
            .toUpperCase();

    final avatar = _photoBytes != null
        ? CircleAvatar(
            radius: radius,
            backgroundImage: MemoryImage(_photoBytes!),
            backgroundColor: Colors.grey.shade100)
        : _resolvePhotoPath(_profile) != null
            ? CircleAvatar(
                radius: radius,
                backgroundImage: NetworkImage(
                    _absolutePhotoUrl(_resolvePhotoPath(_profile)!)),
                backgroundColor: Colors.grey.shade100)
            : CircleAvatar(
                radius: radius,
                backgroundColor: Colors.blue.shade700,
                child: Text(initials,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)));

    return Material(elevation: 4, shape: const CircleBorder(), child: avatar);
  }

  Widget _profileCard(BuildContext context) {
    final nameParts = [
      (_profile?['prenom'] as String?)?.trim(),
      (_profile?['nom'] as String?)?.trim()
    ].where((s) => s != null && s.isNotEmpty).cast<String>().toList();
    final displayName = nameParts.isNotEmpty
        ? nameParts.join(' ')
        : (_profile?['user']?['email'] as String?) ?? _email ?? 'Utilisateur';
    final role = (_profile?['role'] as String?) ?? 'user';
    final email = (_profile?['user']?['email'] as String?) ??
        _profile?['email'] as String? ??
        _email;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black12,
                blurRadius: 14,
                offset: const Offset(0, 6))
          ]),
      child: Row(children: [
        _buildAvatar(36),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(displayName,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.email_outlined, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Flexible(
                child: Text(email ?? '',
                    style: TextStyle(color: Colors.grey.shade700)))
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Chip(
                label: Text(role.toUpperCase()),
                backgroundColor: Colors.blue.shade50),
            if ((_profile?['mfa_enabled'] as bool? ?? false))
              Chip(
                  label: const Text('MFA activée'),
                  backgroundColor: Colors.green.shade50)
            else
              ActionChip(
                  label: const Text('Configurer MFA'),
                  onPressed: () => context.go('/mfa-setup')),
          ]),
        ])),
        IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Éditer le profil',
            onPressed: () async {
              final prev = _profile == null
                  ? null
                  : Map<String, dynamic>.from(_profile!);
              await context.push('/profile/edit');
              await _loadAll(previousProfile: prev);
            }),
      ]),
    );
  }

  List<Map<String, dynamic>> get _combinedActivities {
    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];

    // show local entries first, preserving their synced flag
    for (final a in _localActivities) {
      final key = '${a['text'] ?? ''}::${a['timestamp'] ?? ''}';
      if (!seen.contains(key)) {
        merged.add(a);
        seen.add(key);
      }
    }

    for (final s in _serverActivities) {
      final text = s['text'] ?? s['description'] ?? s.toString();
      final timestamp = s['timestamp']?.toString() ?? '';
      final key = '$text::$timestamp';
      if (!seen.contains(key)) {
        merged.add({
          'text': text.toString(),
          'timestamp': timestamp,
          'raw': s,
          'synced': true
        });
        seen.add(key);
      }
    }
    return merged;
  }

  Widget _recentActivityCard(BuildContext context) {
    final combined = _combinedActivities;
    if (combined.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: const Offset(0, 6))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Activité récente',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text('Aucune activité récente',
              style: TextStyle(color: Colors.grey.shade600)),
        ]),
      );
    }

    return GestureDetector(
      onTap: () => context.go('/history'),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: const Offset(0, 6))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('Activité récente',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ...combined.take(5).map((a) {
            final text = a['text']?.toString() ?? a.toString();
            final ts = (a['timestamp']?.toString() ?? '').isNotEmpty
                ? ' • ${a['timestamp']}'
                : '';
            final synced = a['synced'] == true;
            return ListTile(
              leading: CircleAvatar(
                  radius: 6, backgroundColor: Colors.blue.shade700),
              title: Text(text),
              subtitle: ts.isNotEmpty ? Text(ts) : null,
              trailing: synced
                  ? null
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Text('Non synchronisé',
                          style:
                              TextStyle(fontSize: 11, color: Colors.orange))),
            );
          }).toList(),
          if (combined.length > 5)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text('Voir tout',
                    style: TextStyle(color: Theme.of(context).primaryColor))),
        ]),
      ),
    );
  }

  Widget _actionsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black12,
                blurRadius: 12,
                offset: const Offset(0, 6))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Actions rapides',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ElevatedButton.icon(
            onPressed: () async {
              final prev = _profile == null
                  ? null
                  : Map<String, dynamic>.from(_profile!);
              await context.push('/profile/edit');
              await _loadAll(previousProfile: prev);
            },
            icon: const Icon(Icons.edit),
            label: const Text('Éditer profil')),
        const SizedBox(height: 8),
        ElevatedButton.icon(
            onPressed: () => context.go('/profile-extra'),
            icon: const Icon(Icons.account_balance_wallet),
            label: const Text('Comptes bancaires')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: _loggingOut
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.logout),
            label: const Text('Se déconnecter')),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: () => _loadAll(),
      edgeOffset: 12,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: FadeTransition(
              opacity: _fadeController,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.blue.shade600,
                            Colors.blue.shade400
                          ]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.blue.shade50.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 6))
                          ]),
                      child: Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('Bonjour',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(
                                  (_profile?['prenom'] as String?)?.trim() ??
                                      (_profile?['user']?['email']
                                          as String?) ??
                                      'Utilisateur',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text('Voici votre tableau de bord',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.9))),
                            ])),
                        _buildAvatar(26),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    _profileCard(context),
                    const SizedBox(height: 14),
                    _quickActionsGrid(context),
                    const SizedBox(height: 14),
                    _recentActivityCard(context),
                    const SizedBox(height: 14),
                    _actionsCard(context),
                    const SizedBox(height: 18),
                    Center(
                        child: Text(
                            'Version app: ${AuthService.appVersion ?? "unknown"}',
                            style: TextStyle(color: Colors.grey.shade600))),
                    const SizedBox(height: 24),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Accueil'), elevation: 0, actions: [
        IconButton(
            onPressed: () => _loadAll(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir'),
        IconButton(
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.settings),
            tooltip: 'Paramètres'),
      ]),
      body: _body(context),
      floatingActionButton: FloatingActionButton(
          onPressed: () => context.go('/support'),
          tooltip: 'Aide / Support',
          child: const Icon(Icons.support_agent_outlined)),
    );
  }

  List<String> _computeProfileDiff(
      Map<String, dynamic>? prev, Map<String, dynamic>? next) {
    if (prev == null || next == null) return [];
    final List<String> changes = [];
    String _valueToString(dynamic v) {
      if (v == null) return '';
      if (v is int) return v.toString();
      return v.toString();
    }

    void checkField(String key, String label, {bool allowEmpty = true}) {
      final a = _valueToString(prev[key]);
      final b = _valueToString(next[key]);
      if (a != b) {
        if (!allowEmpty && a.isEmpty && b.isEmpty) return;
        changes.add('$label: "$a" → "$b"');
      }
    }

    checkField('prenom', 'Prénom');
    checkField('nom', 'Nom');
    checkField('email', 'Email');
    checkField('telephone', 'Téléphone');
    checkField('adresse', 'Adresse');
    checkField('lieu_naissance', 'Lieu de naissance');
    checkField('cin_numero', 'Numéro CIN');
    checkField('cin_date_delivrance', 'Date délivrance CIN');
    checkField('nombre_enfants', 'Nombre d\'enfants');
    checkField('sexe', 'Sexe');
    checkField('situation_matrimoniale', 'Situation');
    checkField('role', 'Rôle');

    final prevDate = prev['date_naissance']?.toString() ?? '';
    final nextDate = next['date_naissance']?.toString() ?? '';
    if (prevDate != nextDate)
      changes.add('Date de naissance: "$prevDate" → "$nextDate"');

    final prevPhoto = _resolvePhotoPath(prev);
    final nextPhoto = _resolvePhotoPath(next);
    if (prevPhoto != nextPhoto) {
      if ((prevPhoto ?? '').isEmpty && (nextPhoto ?? '').isNotEmpty)
        changes.add('Photo de profil: ajoutée');
      else if ((prevPhoto ?? '').isNotEmpty && (nextPhoto ?? '').isEmpty)
        changes.add('Photo de profil: supprimée');
      else
        changes.add('Photo de profil: mise à jour');
    }

    return changes;
  }

  Widget _quickActionsGrid(BuildContext context) {
    final crossCount = MediaQuery.of(context).size.width > 720 ? 4 : 2;
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: crossCount,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _quickAction(context, Icons.person, 'Éditer profil', () async {
          final prev =
              _profile == null ? null : Map<String, dynamic>.from(_profile!);
          await context.push('/profile/edit');
          await _loadAll(previousProfile: prev);
        }),
        _quickAction(context, Icons.verified_user, 'Gérer MFA',
            () => context.go('/mfa-setup')),
        _quickAction(context, Icons.account_balance, 'Comptes bancaires',
            () => context.go('/profile-extra')),
        _quickAction(
            context, Icons.history, 'Historique', () => context.go('/history')),
      ],
    );
  }

  Widget _quickAction(
      BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
            color: Theme.of(context).canvasColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade100)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircleAvatar(
              radius: 20,
              backgroundColor: Colors.blue.shade700,
              child: Icon(icon, color: Colors.white, size: 20)),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
