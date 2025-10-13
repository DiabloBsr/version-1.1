// lib/screens/users_list_screen.dart
// Liste des utilisateurs avec :
// - menu/header/footer partagé,
// - recherche réactive (debounce + appel serveur pour >=3 chars),
// - actions Voir/Modifier/Supprimer,
// - format de date en français,
// - hideAdmin option,
// - _HoverNavItem identique à dashboard_screen,
// - résolution robuste de la route courante (évite l'erreur "The getter 'location' isn't defined for the type 'GoRouter'").

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../utils/secure_storage.dart';
import '../services/auth_service.dart';
import '../auth_provider.dart';
import '../auth_state.dart';
import '../state/theme_notifier.dart';

class UsersListScreen extends StatefulWidget {
  final bool hideAdmin;

  const UsersListScreen({Key? key, this.hideAdmin = false}) : super(key: key);

  @override
  State<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> {
  static const _endpoint = '/api/v1/users/all/';

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _visible = [];
  String _query = '';
  int _page = 0;
  final int _pageSize = 25;

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;

  bool get _canUpdate => mounted;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _loadUsers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!_canUpdate) return;
    final q = _searchCtrl.text.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!_canUpdate) return;
      setState(() {
        _query = q;
        _page = 0;
      });
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    if (!_canUpdate) return;
    if (_query.isEmpty) {
      setState(() {
        _visible =
            _users.where((u) => !_filterOutAdmin(u)).toList(growable: false);
      });
      return;
    }
    if (_query.length < 3) {
      final ql = _query.toLowerCase();
      final filtered = _users
          .where((u) {
            final username = (u['username'] ?? '').toString().toLowerCase();
            final email = (u['email'] ?? '').toString().toLowerCase();
            final name = (u['name'] ?? '').toString().toLowerCase();
            return username.contains(ql) ||
                email.contains(ql) ||
                name.contains(ql);
          })
          .where((u) => !_filterOutAdmin(u))
          .toList(growable: false);
      if (!_canUpdate) return;
      setState(() => _visible = filtered);
      return;
    }
    await _searchServer(query: _query, page: 0);
  }

  Future<Uri> _buildUri({String? query, int page = 0}) async {
    const envApiBase = String.fromEnvironment('API_BASE', defaultValue: '');
    final base = envApiBase.isNotEmpty ? envApiBase : 'http://localhost:8000';
    final params = <String, String>{};
    if (query != null && query.isNotEmpty) params['q'] = query;
    params['page'] = (page + 1).toString();
    params['page_size'] = _pageSize.toString();
    return Uri.parse(base + _endpoint)
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<Map<String, String>> _authHeaders() async {
    final access = await SecureStorage.read('access');
    final base = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (access != null && access.isNotEmpty)
      base['Authorization'] = 'Bearer $access';
    return base;
  }

  AuthState? _safeAuth() {
    try {
      return AuthProvider.of(context);
    } catch (_) {
      return null;
    }
  }

  bool _isAdminOrManager(AuthState? auth) {
    if (auth == null) return false;
    final r = auth.role?.toString().toLowerCase() ?? '';
    return r == 'admin' ||
        r.contains('admin') ||
        r.contains('manager') ||
        r.contains('gestionnaire');
  }

  bool _filterOutAdmin(Map<String, dynamic> u) {
    if (!widget.hideAdmin) return false;
    final role = (u['role'] ?? '').toString().toLowerCase();
    return role.contains('admin');
  }

  Future<void> _forceLogoutAndGotoLogin() async {
    try {
      final authState = AuthProvider.of(context);
      await authState.clearAll();
    } catch (_) {}
    if (!_canUpdate) return;
    try {
      context.go('/login');
    } catch (_) {}
  }

  Future<void> _loadUsers({int page = 0}) async {
    if (!_canUpdate) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    Uri uri;
    try {
      uri = await _buildUri(page: page);
    } catch (e) {
      if (!_canUpdate) return;
      setState(() {
        _loading = false;
        _error = 'URL invalide: $e';
      });
      return;
    }

    Future<http.Response> _doGet(Map<String, String> headers) =>
        http.get(uri, headers: headers).timeout(const Duration(seconds: 15));

    try {
      final headers = await _authHeaders();
      final res = await _doGet(headers);

      debugPrint(
          '[UsersList] GET $uri -> status=${res.statusCode}, content-type=${res.headers['content-type']}');
      final snippet =
          res.body.length > 800 ? res.body.substring(0, 800) + '...' : res.body;
      debugPrint('[UsersList] body snippet: $snippet');

      final bodyTrim = res.body.trimLeft();
      if (bodyTrim.startsWith('<') ||
          bodyTrim.toLowerCase().startsWith('<!doctype')) {
        throw FormatException('Le serveur a renvoyé du HTML au lieu de JSON');
      }

      http.Response effective = res;
      if (res.statusCode == 401 || res.statusCode == 403) {
        final refreshed = await AuthService.refreshTokens();
        debugPrint('[UsersList] refreshTokens -> $refreshed');
        if (refreshed) {
          final headers2 = await _authHeaders();
          effective = await _doGet(headers2);
        } else {
          await _forceLogoutAndGotoLogin();
          return;
        }
      }

      if (effective.statusCode == 200) {
        dynamic parsed;
        try {
          parsed = jsonDecode(effective.body);
        } on FormatException catch (fe) {
          throw FormatException('JSON invalide: ${fe.message}');
        }

        List<Map<String, dynamic>> list = [];
        if (parsed is List) {
          list = parsed
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        } else if (parsed is Map && parsed['results'] is List) {
          list = (parsed['results'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        } else {
          throw FormatException('Structure JSON inattendue');
        }

        final filtered =
            list.where((u) => !_filterOutAdmin(u)).toList(growable: false);

        if (!_canUpdate) return;
        setState(() {
          if (page == 0) {
            _users = filtered;
          } else {
            _users = [..._users, ...filtered];
          }
          _visible = _users;
          _loading = false;
          _error = null;
        });
        return;
      }

      String message = 'Erreur serveur (${effective.statusCode})';
      try {
        final parsed = jsonDecode(effective.body);
        if (parsed is Map && parsed['detail'] != null)
          message = parsed['detail'].toString();
        else if (parsed is Map && parsed['message'] != null)
          message = parsed['message'].toString();
      } catch (_) {}
      if (effective.statusCode == 401) {
        await _forceLogoutAndGotoLogin();
        return;
      }
      if (!_canUpdate) return;
      setState(() {
        _loading = false;
        _error = message;
      });
    } on FormatException catch (fe, st) {
      debugPrint('[UsersList] Format error: $fe\n$st');
      if (!_canUpdate) return;
      setState(() {
        _loading = false;
        _error = 'Erreur réseau: ${fe.message}';
      });
    } catch (e, st) {
      debugPrint('[UsersList] error: $e\n$st');
      if (!_canUpdate) return;
      setState(() {
        _loading = false;
        _error = 'Erreur réseau: $e';
      });
    }
  }

  Future<void> _searchServer({required String query, int page = 0}) async {
    if (!_canUpdate) return;
    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final uri = await _buildUri(query: query, page: page);
      final headers = await _authHeaders();
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[UsersList] SEARCH GET $uri -> status=${res.statusCode}');
      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body);
        List<Map<String, dynamic>> list = [];
        if (parsed is List) {
          list = parsed
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        } else if (parsed is Map && parsed['results'] is List) {
          list = (parsed['results'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        } else {
          throw FormatException('Structure JSON inattendue');
        }
        final filtered =
            list.where((u) => !_filterOutAdmin(u)).toList(growable: false);
        if (!_canUpdate) return;
        setState(() {
          _visible = filtered;
          _searching = false;
        });
        return;
      }

      String message = 'Erreur serveur (${res.statusCode})';
      try {
        final parsed = jsonDecode(res.body);
        if (parsed is Map && parsed['detail'] != null)
          message = parsed['detail'].toString();
      } catch (_) {}
      if (!_canUpdate) return;
      setState(() {
        _searching = false;
        _error = message;
      });
    } catch (e, st) {
      debugPrint('[UsersList] search error: $e\n$st');
      if (!_canUpdate) return;
      setState(() {
        _searching = false;
        _error = 'Erreur réseau: $e';
      });
    }
  }

  Future<void> _confirmAndDelete(String id) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer l\'utilisateur'),
        content: const Text(
            'Voulez-vous vraiment supprimer cet utilisateur ? Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (yes != true) return;

    final original = List<Map<String, dynamic>>.from(_users);
    setState(
        () => _users.removeWhere((u) => (u['id'] ?? u['uuid'] ?? '') == id));
    setState(() => _visible =
        _users.where((u) => !_filterOutAdmin(u)).toList(growable: false));

    try {
      final apiBase = String.fromEnvironment('API_BASE',
          defaultValue: 'http://localhost:8000');
      final uri = Uri.parse('$apiBase/api/v1/users/$id/');
      final headers = await _authHeaders();
      final res = await http
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 204 || res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Utilisateur supprimé')));
        return;
      }

      if (!_canUpdate) return;
      setState(() {
        _users = original;
        _visible =
            _users.where((u) => !_filterOutAdmin(u)).toList(growable: false);
      });

      String err = 'Suppression échouée (${res.statusCode})';
      try {
        final parsed = jsonDecode(res.body);
        if (parsed is Map && parsed['detail'] != null)
          err = parsed['detail'].toString();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } catch (e, st) {
      debugPrint('[UsersList] delete error: $e\n$st');
      if (!_canUpdate) return;
      setState(() => _users = _users);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur réseau: $e')));
    }
  }

  InlineSpan _highlightMatch(String text, String query, TextStyle? normalStyle,
      TextStyle? highlightStyle) {
    if (query.isEmpty) return TextSpan(text: text, style: normalStyle);
    final lcText = text.toLowerCase();
    final lcQuery = query.toLowerCase();
    final spans = <InlineSpan>[];
    int start = 0;
    while (true) {
      final idx = lcText.indexOf(lcQuery, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start), style: normalStyle));
        break;
      }
      if (idx > start)
        spans.add(
            TextSpan(text: text.substring(start, idx), style: normalStyle));
      spans.add(TextSpan(
          text: text.substring(idx, idx + lcQuery.length),
          style: highlightStyle));
      start = idx + lcQuery.length;
      if (start >= text.length) break;
    }
    return TextSpan(children: spans);
  }

  String _formatDateReadable(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final day = dt.day;
      final year = dt.year;
      const months = [
        'janvier',
        'février',
        'mars',
        'avril',
        'mai',
        'juin',
        'juillet',
        'août',
        'septembre',
        'octobre',
        'novembre',
        'décembre'
      ];
      final month = months[dt.month - 1];
      return '$day $month $year';
    } catch (_) {
      return isoDate;
    }
  }

  // Résolution robuste de la route courante :
  // 1) tentative d'accès dynamique à `router.location` pour éviter l'erreur d'analyseur
  // 2) fallback sur ModalRoute.settings.name
  // 3) fallback sur Uri.base.path
  String _resolveCurrentLocation(BuildContext context) {
    // 1) accès dynamique à GoRouter pour contourner les différences d'API entre versions
    try {
      final router = GoRouter.of(context);
      // utiliser `dynamic` pour éviter l'erreur statique si la version de go_router n'expose pas `.location`
      final dyn = router as dynamic;
      final loc = dyn.location;
      if (loc is String && loc.isNotEmpty) return loc;
    } catch (_) {
      // ignore et fallback
    }

    // 2) fallback : ModalRoute name
    try {
      final modal = ModalRoute.of(context)?.settings.name;
      if (modal != null && modal.isNotEmpty) return modal;
    } catch (_) {}

    // 3) fallback : Uri.base.path (path courant du navigateur)
    try {
      final path = Uri.base.path;
      if (path.isNotEmpty) return path;
    } catch (_) {}

    return '/';
  }

  // Side nav: compute activeRoute from resolved location
  Widget _sideNav(BuildContext context, bool expanded, String userEmail) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? Colors.blueGrey.shade900 : theme.colorScheme.primary;
    final colorOn = theme.colorScheme.onPrimary;

    final current = _resolveCurrentLocation(context);
    String activeRoute;
    if (current.startsWith('/users')) {
      activeRoute = '/personnel';
    } else if (current.startsWith('/dashboard') ||
        current == '/' ||
        current.startsWith('/home')) {
      activeRoute = '/dashboard';
    } else if (current.startsWith('/birthdays')) {
      activeRoute = '/birthdays';
    } else if (current.startsWith('/planning')) {
      activeRoute = '/planning';
    } else if (current.startsWith('/settings')) {
      activeRoute = '/settings';
    } else {
      activeRoute = current;
    }

    return Container(
      width: expanded ? 240 : 72,
      color: bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 16 : 8, vertical: 16),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.white30,
                        shape: BoxShape.circle),
                    child: Icon(Icons.business, color: colorOn)),
                if (expanded) const SizedBox(width: 12),
                if (expanded)
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('BotaApp',
                            style: TextStyle(
                                color: colorOn, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(userEmail,
                            style: TextStyle(
                                color: colorOn.withOpacity(0.9), fontSize: 12),
                            overflow: TextOverflow.ellipsis)
                      ])),
              ]),
            ),
            const Divider(height: 1, color: Colors.white24),
            const SizedBox(height: 8),
            _HoverNavItem(
                icon: Icons.dashboard,
                label: 'Dashboard',
                route: '/dashboard',
                expanded: expanded,
                activeRoute: activeRoute,
                onTap: _onNavTap),
            _HoverNavItem(
                icon: Icons.people,
                label: 'Personnel',
                route: '/personnel',
                expanded: expanded,
                activeRoute: activeRoute,
                onTap: _onNavTap),
            _HoverNavItem(
                icon: Icons.cake,
                label: 'Anniversaires',
                route: '/birthdays',
                expanded: expanded,
                activeRoute: activeRoute,
                onTap: _onNavTap),
            _HoverNavItem(
                icon: Icons.calendar_today,
                label: 'Planning',
                route: '/planning',
                expanded: expanded,
                activeRoute: activeRoute,
                onTap: _onNavTap),
            _HoverNavItem(
                icon: Icons.settings,
                label: 'Paramètres',
                route: '/settings',
                expanded: expanded,
                activeRoute: activeRoute,
                onTap: _onNavTap),
            const Spacer(),
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 16 : 8, vertical: 12),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    minimumSize: const Size.fromHeight(44)),
                onPressed: () async {
                  try {
                    final auth = AuthProvider.of(context);
                    await auth.clearAll();
                  } catch (_) {}
                  try {
                    context.go('/login');
                  } catch (_) {}
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Se déconnecter'),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _onNavTap(String route) {
    final auth = _safeAuth();
    if (route == '/personnel' && _isAdminOrManager(auth)) {
      try {
        context.go('/users');
      } catch (_) {}
      return;
    }
    try {
      context.go(route);
    } catch (_) {}
  }

  Widget _header(BuildContext context, double contentWidth, String userEmail) {
    final theme = Theme.of(context);
    final tn = ThemeNotifier.safeOf(context);
    final isDark = tn?.isDark ?? (theme.brightness == Brightness.dark);
    return Material(
      elevation: 4,
      color: theme.colorScheme.surface,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Expanded(
                child: Text('Liste des utilisateurs',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold))),
            SizedBox(
              width: contentWidth >= 800 ? 420 : 240,
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Rechercher par nom, username ou email...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceVariant,
                    isDense: true,
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)))
                        : null),
                onSubmitted: (_) => _performSearch(),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(onPressed: _loadUsers, icon: const Icon(Icons.refresh)),
            IconButton(
              tooltip: isDark ? 'Passer en clair' : 'Passer en sombre',
              onPressed: () {
                if (tn != null) {
                  tn.toggle();
                  if (mounted) setState(() {});
                }
              },
              icon: Icon(isDark
                  ? Icons.wb_sunny_outlined
                  : Icons.nights_stay_outlined),
            ),
            const SizedBox(width: 12),
            CircleAvatar(
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                    (userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'U'))),
          ],
        ),
      ),
    );
  }

  Widget _userCard(BuildContext context, Map<String, dynamic> u) {
    final theme = Theme.of(context);
    final id = (u['id'] ?? u['uuid'] ?? '').toString();
    final name = (u['username'] ?? u['name'] ?? 'Inconnu').toString();
    final email = (u['email'] ?? '').toString();
    final joinedRaw = (u['date_joined'] ?? u['created_at'] ?? '')?.toString();
    final joined = _formatDateReadable(joinedRaw);
    final active = u['is_active'] == true;

    final normalStyle = theme.textTheme.bodyMedium;
    final highlightStyle = normalStyle?.copyWith(
        backgroundColor: theme.colorScheme.primary.withOpacity(0.18),
        fontWeight: FontWeight.w700);

    return Card(
      elevation: 1,
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(color: theme.colorScheme.primary))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                        text: _highlightMatch(name, _query,
                            theme.textTheme.titleMedium, highlightStyle)),
                    const SizedBox(height: 4),
                    if (email.isNotEmpty)
                      RichText(
                          text: _highlightMatch(email, _query,
                              theme.textTheme.bodySmall, highlightStyle)),
                    if (joined.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Inscrit le: $joined',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6)))),
                  ]),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(active ? Icons.check_circle : Icons.remove_circle,
                    color: active ? Colors.green : Colors.grey),
                const SizedBox(height: 8),
                Row(children: [
                  IconButton(
                      tooltip: 'Voir',
                      onPressed: () {
                        if (id.isEmpty) return;
                        try {
                          context.push('/users/$id');
                        } catch (_) {
                          try {
                            context.push('/profile/$id');
                          } catch (_) {}
                        }
                      },
                      icon: const Icon(Icons.visibility)),
                  IconButton(
                      tooltip: 'Modifier',
                      onPressed: () {
                        if (id.isEmpty) return;
                        try {
                          context.push('/users/$id/edit');
                        } catch (_) {
                          try {
                            context.push('/profile/$id/edit');
                          } catch (_) {}
                        }
                      },
                      icon: const Icon(Icons.edit)),
                  IconButton(
                      tooltip: 'Supprimer',
                      onPressed: () {
                        if (id.isEmpty) return;
                        _confirmAndDelete(id);
                      },
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent)),
                ])
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Erreur',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
                onPressed: _loadUsers,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer')),
          ]),
        ),
      );
    }

    if (_visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
            child: Text('Aucun résultat', style: theme.textTheme.bodyLarge)),
      );
    }

    final userCards =
        _visible.map((u) => _userCard(context, u)).toList(growable: false);

    if (screenWidth >= 1000) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 3.6,
          children: userCards,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemBuilder: (_, i) => userCards[i],
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: userCards.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = _safeAuth();
    final userEmail = auth?.userEmail ?? '';
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final useFixedNav = kIsWeb || screenWidth >= 900;
    final navExpanded = screenWidth >= 1100;
    final contentMaxWidth = screenWidth > 1200
        ? 1200.0
        : (screenWidth - (useFixedNav ? (navExpanded ? 240 : 72) : 0) - 48);

    Widget footer = Container(
      color: theme.colorScheme.surfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Expanded(
              child: Text('© ${DateTime.now().year} BotaApp — Gestion RH',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          Wrap(spacing: 8, children: [
            ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.business, size: 16),
                label: const Text('LinkedIn')),
            OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.code, size: 16),
                label: const Text('GitHub')),
          ])
        ],
      ),
    );

    if (useFixedNav) {
      return Scaffold(
        bottomNavigationBar: footer,
        body: Row(
          children: [
            _sideNav(context, navExpanded, userEmail),
            Expanded(
              child: Column(
                children: [
                  _header(context, contentMaxWidth, userEmail),
                  Expanded(child: _content(context)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      bottomNavigationBar: footer,
      appBar: AppBar(title: const Text('Utilisateurs'), actions: [
        IconButton(onPressed: _loadUsers, icon: const Icon(Icons.refresh))
      ]),
      drawer:
          Drawer(child: SafeArea(child: _sideNav(context, true, userEmail))),
      body: SafeArea(child: _content(context)),
    );
  }
}

/// Nav item with hover feedback (same as dashboard_screen)
class _HoverNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String route;
  final bool expanded;
  final String activeRoute;
  final void Function(String route) onTap;

  const _HoverNavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.expanded,
    required this.activeRoute,
    required this.onTap,
  });

  @override
  State<_HoverNavItem> createState() => _HoverNavItemState();
}

class _HoverNavItemState extends State<_HoverNavItem>
    with SingleTickerProviderStateMixin {
  bool _hovering = false;
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 180),
        lowerBound: 0.0,
        upperBound: 6.0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _setHover(bool v) {
    if (!mounted) return;
    setState(() => _hovering = v);
    if (v)
      _anim.forward();
    else
      _anim.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isActive = widget.activeRoute == widget.route;
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final baseColor = Colors.white;
      final bgColor = isActive
          ? Colors.white.withOpacity(isDark ? 0.08 : 0.15)
          : (_hovering
              ? Colors.white.withOpacity(isDark ? 0.06 : 0.08)
              : Colors.transparent);

      final showLabel = widget.expanded && constraints.maxWidth >= 120;
      final horizontalPadding = showLabel ? 14.0 : 6.0;
      final verticalPadding = showLabel ? 8.0 : 6.0;

      final inner = AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding, vertical: verticalPadding),
        decoration: BoxDecoration(
            color: bgColor, borderRadius: BorderRadius.circular(12)),
        child: GestureDetector(
          onTap: () => widget.onTap(widget.route),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _anim,
                builder: (context, child) {
                  return Transform.translate(
                      offset: Offset(_anim.value, 0), child: child);
                },
                child: Container(
                  height: 40,
                  width: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white30
                        : (_hovering ? Colors.white12 : Colors.transparent),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.icon, color: baseColor, size: 22),
                ),
              ),
              if (showLabel) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(
                        color: baseColor,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 15),
                    child: Text(widget.label, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

      if (!widget.expanded) {
        return MouseRegion(
          onEnter: (_) => _setHover(true),
          onExit: (_) => _setHover(false),
          cursor: SystemMouseCursors.click,
          child: Tooltip(
              message: widget.label,
              waitDuration: const Duration(milliseconds: 200),
              showDuration: const Duration(seconds: 2),
              child: inner),
        );
      }

      return MouseRegion(
          onEnter: (_) => _setHover(true),
          onExit: (_) => _setHover(false),
          cursor: SystemMouseCursors.click,
          child: inner);
    });
  }
}
