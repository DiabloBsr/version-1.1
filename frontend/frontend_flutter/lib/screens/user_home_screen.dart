// lib/screens/user_home_screen.dart
// ignore_for_file: unused_field

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

  // Activities
  List<Map<String, dynamic>> _localActivities = [];
  List<Map<String, dynamic>> _serverActivities = [];

  // Bank account state
  bool _hasBankAccount = false;
  String? _primaryBankAccountId;
  List<Map<String, dynamic>> _bankAccounts = [];

  // Activity filter state removed; we always display recent activities with tags
  String _activityFilter = 'all';

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
      await _reconcileStoredLocalActivities();

      final profile = await AuthService.getProfile();
      if (profile == null) {
        if (mounted) context.go('/login');
        return;
      }
      if (mounted) setState(() => _profile = profile);
      _email = (profile['user'] is Map)
          ? profile['user']['email'] as String?
          : profile['email'] as String?;

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

          if (remain.isNotEmpty) await _storeLocalActivities(remain);
          setState(() => _localActivities = [...entries, ..._localActivities]);
        }
      }

      _serverActivities = await AuthService.getActivities(limit: 100);

      // Load bank accounts for profile
      try {
        final profileId =
            _profile?['id'] ?? _profile?['pk'] ?? _profile?['uuid'];
        if (profileId != null) {
          final accounts = await AuthService.getBankAccounts(
              profileId: profileId.toString());
          if (accounts != null && accounts.isNotEmpty) {
            setState(() {
              _bankAccounts = List<Map<String, dynamic>>.from(accounts);
              _hasBankAccount = true;
              final primary = _bankAccounts.firstWhere(
                  (a) => a['is_primary'] == true,
                  orElse: () => _bankAccounts.first);
              _primaryBankAccountId = primary['id']?.toString();
            });
          } else {
            setState(() {
              _bankAccounts = [];
              _hasBankAccount = false;
              _primaryBankAccountId = null;
            });
          }
        }
      } catch (e) {
        debugPrint('[UserHome] getBankAccounts error: $e');
        setState(() {
          _bankAccounts = [];
          _hasBankAccount = false;
          _primaryBankAccountId = null;
        });
      }

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
        if (e['synced'] == true) continue;
        try {
          final posted = await AuthService.postActivity(e);
          if (!posted) failures.add(e);
        } catch (err) {
          debugPrint('[UserHome] reconcile postActivity error: $err');
          failures.add(e);
        }
      }

      if (failures.isEmpty) {
        await SecureStorage.delete('local_activities');
      } else {
        await SecureStorage.write('local_activities', jsonEncode(failures));
      }

      final unsynced = failures;
      setState(() => _localActivities = [...unsynced, ..._localActivities]);
    } catch (e, st) {
      debugPrint('[UserHome] _reconcileStoredLocalActivities error: $e\n$st');
    }
  }

  Future<void> _storeLocalActivities(List<Map<String, dynamic>> entries) async {
    try {
      final normalized = entries.map((e) {
        final m = Map<String, dynamic>.from(e);
        m['synced'] = m['synced'] == true;
        return m;
      }).toList();

      final raw = await SecureStorage.read('local_activities');
      List existing = raw != null ? jsonDecode(raw) as List : [];
      existing = [...normalized, ...existing];
      await SecureStorage.write('local_activities', jsonEncode(existing));
      debugPrint('[UserHome] stored local activities: ${normalized.length}');
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
      // Redirect immediately to the login screen after logout
      if (!mounted) return;
      context.go('/login'); // ensure direct navigation to login_screen
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur lors de la déconnexion: $e')));
      }
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Widget _buildAvatar(double radius) {
    final first = (_profile?['prenom'] as String?)?.trim() ?? '';
    final last = (_profile?['nom'] as String?)?.trim() ?? '';
    final name = [first, last].where((s) => s.isNotEmpty).join(' ');
    String initials;
    if (name.isNotEmpty) {
      initials = name
          .split(' ')
          .where((s) => s.isNotEmpty)
          .map((s) => s[0])
          .join()
          .toUpperCase();
    } else {
      final emailOr = (_profile?['user']?['email'] as String?) ?? _email ?? 'U';
      initials = (emailOr.isNotEmpty ? emailOr[0] : 'U').toUpperCase();
    }

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

  // Combine local and server activities and normalize with a category detection
  List<Map<String, dynamic>> get _combinedActivities {
    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];

    // local first (unsynced first)
    for (final a in _localActivities) {
      final key = '${a['text'] ?? ''}::${a['timestamp'] ?? ''}';
      if (!seen.contains(key)) {
        final m = Map<String, dynamic>.from(a);
        m['category'] = _detectCategory(m);
        merged.add(m);
        seen.add(key);
      }
    }

    // server activities
    for (final s in _serverActivities) {
      final text = s['text'] ?? s['description'] ?? s.toString();
      final timestamp = s['timestamp']?.toString() ?? '';
      final key = '$text::$timestamp';
      if (!seen.contains(key)) {
        final item = {
          'text': text.toString(),
          'timestamp': timestamp,
          'raw': s,
          'synced': true,
        };
        item['category'] = _detectCategory(s);
        merged.add(item);
        seen.add(key);
      }
    }

    return merged;
  }

  // Heuristic to detect bank-account related activities
  String _detectCategory(dynamic entry) {
    try {
      if (entry is Map) {
        final t = (entry['type'] as String?) ?? '';
        if (t == 'bank_account' || t == 'bank') return 'bank_account';
        final meta = entry['meta'];
        if (meta is Map) {
          final resource = (meta['resource'] as String?) ??
              (meta['resource_type'] as String?);
          if (resource != null && resource.toLowerCase().contains('bank')) {
            return 'bank_account';
          }
          final source = (meta['source'] as String?) ?? '';
          if (source.toLowerCase().contains('bank')) return 'bank_account';
          final accountId = meta['account_id'] ?? meta['resource_id'];
          if (accountId != null) return 'bank_account';
        }
        final text = (entry['text'] ?? entry['description'] ?? '')
            .toString()
            .toLowerCase();
        if (text.contains('compte') ||
            text.contains('banc') ||
            text.contains('iban') ||
            text.contains('banque')) {
          return 'bank_account';
        }
      } else {
        final s = entry.toString().toLowerCase();
        if (s.contains('compte') ||
            s.contains('banque') ||
            s.contains('iban')) {
          return 'bank_account';
        }
      }
    } catch (_) {}
    return 'general';
  }

  Widget _recentActivityCard(BuildContext context) {
    final combined = _combinedActivities;
    final filtered = combined; // show all, tags indicate types

    if (filtered.isEmpty) {
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
          Text('Aucune activité correspondante',
              style: TextStyle(color: Colors.grey.shade600)),
        ]),
      );
    }

    return Container(
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
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                const Expanded(
                    child: Text('Activité récente',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700))),
              ],
            )),
        ...filtered.take(6).map((a) {
          final text = a['text']?.toString() ?? a.toString();
          final tsStr = (a['timestamp']?.toString() ?? '');
          final ts = tsStr.isNotEmpty ? ' • ${_formatTimestamp(tsStr)}' : '';
          final synced = a['synced'] == true;
          final category = a['category'] as String? ?? 'general';

          Widget tagFor(String category) {
            if (category == 'bank_account') {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('Compte',
                    style:
                        TextStyle(color: Colors.green.shade800, fontSize: 11)),
              );
            }
            if (category == 'profile_change' ||
                (a['type'] == 'profile_change')) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('Profil',
                    style:
                        TextStyle(color: Colors.blue.shade800, fontSize: 11)),
              );
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('Général',
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 11)),
            );
          }

          return ListTile(
            leading: CircleAvatar(
                radius: 6,
                backgroundColor: category == 'bank_account'
                    ? Colors.green.shade700
                    : Colors.blue.shade700),
            title: Text(text),
            subtitle: ts.isNotEmpty ? Text(ts) : null,
            trailing:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (!synced)
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Text('Non synchronisé',
                        style: TextStyle(fontSize: 11, color: Colors.orange))),
              const SizedBox(height: 6),
              tagFor(category),
            ]),
            onTap: () {
              if (a['category'] == 'bank_account') {
                context.go('/bank-accounts');
              } else {
                context.go('/history');
              }
            },
          );
        }).toList(),
        if (filtered.length > 6)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('Voir tout',
                  style: TextStyle(color: Theme.of(context).primaryColor))),
      ]),
    );
  }

  String _formatTimestamp(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat.yMMMd().add_jm().format(dt);
    } catch (_) {
      return iso;
    }
  }

  // Left-side fixed menu (with hover effect)
  Widget _leftFixedMenu(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 10, offset: Offset(0, 6))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Actions rapides',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).textTheme.bodyMedium?.color)),
            const SizedBox(height: 12),
            MenuButton(
              icon: Icons.person,
              label: 'Éditer profil',
              onTap: () async {
                final prev = _profile == null
                    ? null
                    : Map<String, dynamic>.from(_profile!);
                await context.push('/profile/edit');
                await _loadAll(previousProfile: prev);
              },
            ),
            const SizedBox(height: 8),
            MenuButton(
              icon: Icons.account_balance,
              label: _hasBankAccount
                  ? 'Afficher compte bancaire'
                  : 'Ajouter compte bancaire',
              onTap: () => context.go(
                  _hasBankAccount ? '/bank-accounts' : '/bank-account/create'),
            ),
            const SizedBox(height: 8),
            MenuButton(
              icon: Icons.history,
              label: 'Historique',
              onTap: () => context.go('/history'),
            ),
            const SizedBox(height: 8),
            MenuButton(
              icon: Icons.logout,
              label: 'Se déconnecter',
              color: Colors.orange,
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard(BuildContext context) {
    final nameParts = [
      (_profile?['prenom'] as String?)?.trim(),
      (_profile?['nom'] as String?)?.trim()
    ].where((s) => s != null && s.isNotEmpty).cast<String>().toList();
    final displayName = nameParts.isNotEmpty
        ? nameParts.join(' ')
        : (_profile?['user']?['email'] as String?) ?? _email ?? 'Utilisateur';
    final email = (_profile?['user']?['email'] as String?) ??
        _profile?['email'] as String? ??
        _email;

    // Dynamic bank message: if linked, show bank name; else prompt to link
    String bankMessage;
    if (_hasBankAccount && _bankAccounts.isNotEmpty) {
      final bank = _bankAccounts.first;
      final bankName =
          (bank['bank_name'] ?? bank['bank'] ?? bank['name'] ?? 'Banque')
              .toString();
      bankMessage = 'Compte bancaire $bankName lié';
    } else {
      bankMessage = 'Veuillez lier un compte bancaire';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, 6))
        ],
      ),
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
              // Bank message chip with contextual action
              Chip(
                label: Text(bankMessage),
                backgroundColor: _hasBankAccount
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                labelStyle: TextStyle(
                    color: _hasBankAccount
                        ? Colors.green.shade800
                        : Colors.orange.shade800),
              ),
              if (!_hasBankAccount)
                ActionChip(
                  label: const Text('Lier un compte'),
                  onPressed: () => context.go('/bank-account/create'),
                )
              else
                ActionChip(
                  label: const Text('Voir le compte'),
                  onPressed: () => context.go('/bank-accounts'),
                ),
              // Optional employment status chip if present
              if ((_profile?['employment'] as String?) != null &&
                  (_profile!['employment'] as String).trim().isNotEmpty)
                Chip(
                  label:
                      Text((_profile!['employment'] as String).toUpperCase()),
                  backgroundColor: Colors.blue.shade50,
                  labelStyle: TextStyle(color: Colors.blue.shade800),
                ),
            ]),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.edit),
          tooltip: 'Éditer le profil',
          onPressed: () async {
            final prev =
                _profile == null ? null : Map<String, dynamic>.from(_profile!);
            await context.push('/profile/edit');
            await _loadAll(previousProfile: prev);
          },
        ),
      ]),
    );
  }

  Widget _quickActionsGridPlaceholder(BuildContext context) {
    // kept for layout consistency on narrow screens — actions moved to left menu
    final crossCount = MediaQuery.of(context).size.width > 720 ? 4 : 2;
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: crossCount,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _quickTile(context, Icons.person, 'Éditer profil', () async {
          final prev =
              _profile == null ? null : Map<String, dynamic>.from(_profile!);
          await context.push('/profile/edit');
          await _loadAll(previousProfile: prev);
        }),
        _quickTile(context, Icons.account_balance,
            _hasBankAccount ? 'Compte bancaire' : 'Ajouter compte bancaire',
            () {
          context
              .go(_hasBankAccount ? '/bank-accounts' : '/bank-account/create');
        }),
        _quickTile(
            context, Icons.history, 'Historique', () => context.go('/history')),
        _quickTile(
            context, Icons.logout, 'Se déconnecter', () => _logout(context)),
      ],
    );
  }

  Widget _quickTile(
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

  Widget _bodyMain(BuildContext context) {
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
                        ],
                      ),
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
                    // Keep compact quick actions for very narrow screens; main quick actions live in left menu
                    if (MediaQuery.of(context).size.width <= 720) ...[
                      _quickActionsGridPlaceholder(context),
                      const SizedBox(height: 14),
                    ],
                    _recentActivityCard(context),
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

  // Fixed footer widget (no service client link; floating button remains)
  Widget _fixedFooter(BuildContext context) {
    final version = AuthService.appVersion ?? 'unknown';
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text('Version: $version',
              style: TextStyle(color: Colors.grey.shade700)),
          const Spacer(),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Layout: left fixed menu + main content, footer fixed at bottom
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
      body: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left fixed menu (hidden on very narrow viewports)
                LayoutBuilder(builder: (context, constraints) {
                  if (constraints.maxWidth < 1000) {
                    // narrow: hide left menu; mobile sees quick actions inline
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding:
                        const EdgeInsets.only(left: 18, top: 18, bottom: 18),
                    child: _leftFixedMenu(context),
                  );
                }),
                // Main scrollable content
                Expanded(child: _bodyMain(context)),
              ],
            ),
          ),
          // Fixed footer
          _fixedFooter(context),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/support'),
        tooltip: 'Aide / Support',
        child: const Icon(Icons.support_agent_outlined),
      ),
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
    if (prevDate != nextDate) {
      changes.add('Date de naissance: "$prevDate" → "$nextDate"');
    }

    final prevPhoto = _resolvePhotoPath(prev);
    final nextPhoto = _resolvePhotoPath(next);
    if (prevPhoto != nextPhoto) {
      if ((prevPhoto ?? '').isEmpty && (nextPhoto ?? '').isNotEmpty) {
        changes.add('Photo de profil: ajoutée');
      } else if ((prevPhoto ?? '').isNotEmpty && (nextPhoto ?? '').isEmpty) {
        changes.add('Photo de profil: supprimée');
      } else {
        changes.add('Photo de profil: mise à jour');
      }
    }

    return changes;
  }
}

/// Small reusable menu button widget with hover effect
class MenuButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const MenuButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  }) : super(key: key);

  @override
  State<MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<MenuButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovering
        ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
        : Colors.transparent;
    final iconBg = _hovering ? Theme.of(context).colorScheme.primary : null;
    final textColor = _hovering ? Theme.of(context).colorScheme.primary : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      iconBg ?? widget.color ?? Colors.blue.shade700,
                  child: Icon(widget.icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: textColor ??
                          Theme.of(context).textTheme.bodyMedium?.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_hovering)
                  Icon(Icons.arrow_forward_ios,
                      size: 14,
                      color: textColor ??
                          Theme.of(context).textTheme.bodyMedium?.color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
