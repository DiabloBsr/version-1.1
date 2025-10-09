// lib/screens/dashboard_screen.dart
// ignore_for_file: unused_local_variable, unused_field, unnecessary_null_comparison

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/dashboard_service.dart';
import '../models/dashboard_summary.dart';
import '../auth_provider.dart';
import '../auth_state.dart';
import '../utils/secure_storage.dart';
import '../services/auth_service.dart';
import '../state/theme_notifier.dart';
import '../widgets/section_card.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _service = DashboardService();
  Future<DashboardSummary?>? _futureSummary;
  String? _error;
  bool _loading = true;
  String _activeRoute = '/dashboard';
  final bool _navExpanded = true;
  final TextEditingController _searchCtrl = TextEditingController();

  // lifecycle guard
  bool _disposed = false;

  // Breakpoints used across the screen
  static const double narrowWidth = 720;
  static const double mediumWidth = 1024;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _canUpdate => mounted && !_disposed;

  Future<void> _safeGo(String route) async {
    if (!_canUpdate) return;
    if (mounted) {
      Future.microtask(() {
        if (!mounted) return;
        try {
          context.go(route);
        } catch (_) {}
      });
    }
  }

  Future<void> _loadSummary() async {
    if (!_canUpdate) return;
    setState(() {
      _loading = true;
      _error = null;
      _futureSummary = null;
    });

    final access = await SecureStorage.read('access');
    if (!_canUpdate) return;
    if (access == null || access.isEmpty) {
      if (!_canUpdate) return;
      setState(() {
        _error = 'Token manquant. Veuillez vous reconnecter.';
        _loading = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!_canUpdate) return;
      _safeGo('/login');
      return;
    }

    try {
      final data = await _service.fetchDashboardSummary();
      if (!_canUpdate) return;
      final summary = DashboardSummary.fromJson(data);
      if (!_canUpdate) return;
      setState(() {
        _futureSummary = Future.value(summary);
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('[Dashboard] fetch error: $e\n$st');

      final refreshed = await AuthService.refreshTokens();
      if (!_canUpdate) return;
      if (refreshed) {
        if (!_canUpdate) return;
        return _loadSummary();
      }

      try {
        final auth = AuthProvider.of(context);
        await auth.clearAll();
      } catch (_) {}

      if (!_canUpdate) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });

      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!_canUpdate) return;
      _safeGo('/login');
    }
  }

  AuthState? _safeAuthState() {
    try {
      return AuthProvider.of(context);
    } catch (_) {
      return null;
    }
  }

  void _onNavigate(String route) {
    if (!_canUpdate) return;
    setState(() => _activeRoute = route);
    if (!kIsWeb && mounted) Navigator.pop(context);
    if (!_canUpdate) return;
    try {
      context.go(route);
    } catch (e, st) {
      debugPrint('Navigation failed: $e\n$st');
    }
  }

  // Heuristics to compute active users and "new this month" from summary data.
  // Assumptions:
  // - DashboardSummary may expose a users list (summary.users) where each user map contains:
  //    'is_active' (bool) and 'date_joined' (ISO string) or 'created_at'
  // - If summary already provides aggregated counts (summary.activePersonnel, summary.newThisMonth),
  //   we prefer those fields.
  int _computeActiveFromSummary(DashboardSummary s) {
    try {
      // prefer provided aggregate
      final provided = s.activePersonnel;
      if (provided != null) return provided;
    } catch (_) {}
    try {
      final users = s.users;
      if (users is List) {
        return users.where((u) {
          try {
            final isActive = (u['is_active'] ?? u['active'] ?? false) as bool;
            return isActive;
          } catch (_) {
            return false;
          }
        }).length;
      }
    } catch (_) {}
    // fallback to summary.activePersonnel if non-null, else 0
    return (s.activePersonnel);
  }

  int _computeNewThisMonthFromSummary(DashboardSummary s) {
    try {
      final provided = s.newThisMonth;
      if (provided != null) return provided;
    } catch (_) {}
    try {
      final users = s.users;
      if (users is List) {
        final now = DateTime.now();
        final year = now.year;
        final month = now.month;
        return users.where((u) {
          try {
            final raw = u['date_joined'] ??
                u['created_at'] ??
                u['created'] ??
                u['date'];
            if (raw == null) return false;
            final dt = DateTime.parse(raw.toString());
            return dt.year == year &&
                dt.month == month &&
                dt.isBefore(now.add(const Duration(seconds: 1)));
          } catch (_) {
            return false;
          }
        }).length;
      }
    } catch (_) {}
    // fallback
    return (s.newThisMonth);
  }

  Widget _sideNavExpanded(bool expanded, String userEmail, ThemeData theme) {
    final effectiveWidth = expanded ? 240.0 : 72.0;
    return Container(
      width: effectiveWidth,
      color: Colors.blue.shade900,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 16 : 8, vertical: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.white30, shape: BoxShape.circle),
                    child: const Icon(Icons.business,
                        color: Colors.white, size: 28),
                  ),
                  if (expanded)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('BotaApp',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(userEmail,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 12),
            _HoverNavItem(
                icon: Icons.dashboard,
                label: 'Dashboard',
                route: '/dashboard',
                expanded: expanded,
                activeRoute: _activeRoute,
                onTap: _onNavigate),
            _HoverNavItem(
                icon: Icons.people,
                label: 'Personnel',
                route: '/personnel',
                expanded: expanded,
                activeRoute: _activeRoute,
                onTap: _onNavigate),
            _HoverNavItem(
                icon: Icons.cake,
                label: 'Anniversaires',
                route: '/birthdays',
                expanded: expanded,
                activeRoute: _activeRoute,
                onTap: _onNavigate),
            _HoverNavItem(
                icon: Icons.calendar_today,
                label: 'Planning',
                route: '/planning',
                expanded: expanded,
                activeRoute: _activeRoute,
                onTap: _onNavigate),
            _HoverNavItem(
                icon: Icons.settings,
                label: 'Paramètres',
                route: '/settings',
                expanded: expanded,
                activeRoute: _activeRoute,
                onTap: _onNavigate),
            const Spacer(),
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 16 : 8, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 12),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () async {
                    if (!_canUpdate) return;
                    try {
                      final auth = AuthProvider.of(context);
                      await auth.clearAll();
                    } catch (_) {}
                    if (!_canUpdate) return;
                    _safeGo('/login');
                  },
                  icon: const Icon(Icons.logout, size: 18),
                  label: FittedBox(
                      child: Text('Se déconnecter',
                          overflow: TextOverflow.ellipsis)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _statCards(
      DashboardSummary summary, ThemeData theme, double contentWidth) {
    // compute dynamic values
    final totalUsers = summary.totalUsers ??
        (summary.users is List ? (summary.users as List).length : 0);
    final activePersonnel = _computeActiveFromSummary(summary);
    final newThisMonth = _computeNewThisMonthFromSummary(summary);

    // build cards. make "Total utilisateurs" clickable -> navigate to '/users' (admin list)
    final cards = [
      GestureDetector(
        onTap: () {
          if (!_canUpdate) return;
          try {
            context.go('/users'); // route showing full list of users
          } catch (e) {
            debugPrint('Navigation to /users failed: $e');
          }
        },
        child: StatCard(
          title: "Total utilisateurs",
          value: totalUsers.toString(),
          color: theme.colorScheme.primary,
          icon: Icons.people,
        ),
      ),
      StatCard(
          title: "Personnel actif",
          value: activePersonnel.toString(),
          color: Colors.green.shade600,
          icon: Icons.check_circle),
      StatCard(
          title: "Nouveaux ce mois",
          value: newThisMonth.toString(),
          color: Colors.orange.shade600,
          icon: Icons.add),
    ];

    const gap = 16.0;
    final available = contentWidth;
    final int columns = available >= 1200 ? 3 : (available >= 800 ? 2 : 1);
    final double cardMaxWidth = (available - gap * (columns - 1)) / columns;

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: cards.map((c) {
        return ConstrainedBox(
          constraints: BoxConstraints(minWidth: 120, maxWidth: cardMaxWidth),
          child: c,
        );
      }).toList(),
    );
  }

  Widget _emptyPlaceholder(BuildContext context, String text,
      {IconData icon = Icons.inbox}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 48, color: theme.colorScheme.primary.withOpacity(0.12)),
          const SizedBox(height: 12),
          Text(text,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildHeader(
      double contentWidth, ThemeData theme, String userEmail, bool hideTitle) {
    final ThemeNotifier? tn = ThemeNotifier.safeOf(context);
    final bool isDark = tn?.isDark ?? (theme.brightness == Brightness.dark);

    return Material(
      elevation: 4,
      color: theme.colorScheme.surface,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentWidth),
            child: Row(
              children: [
                if (!hideTitle)
                  Expanded(
                    child: Text('Tableau de bord RH',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  )
                else
                  const Spacer(),
                Flexible(
                  flex: 0,
                  child: SizedBox(
                    width: contentWidth >= 800
                        ? 420
                        : (contentWidth >= 600 ? 320 : 160),
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 12),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: 'Rechercher...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceVariant,
                        isDense: true,
                      ),
                      onSubmitted: (q) {
                        if (!_canUpdate) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Recherche: $q')));
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                    onPressed: () {},
                    icon: Icon(Icons.notifications_none,
                        color: theme.iconTheme.color)),
                IconButton(
                  tooltip: isDark ? 'Passer en clair' : 'Passer en sombre',
                  onPressed: () {
                    if (!_canUpdate) return;
                    if (tn != null) tn.toggle();
                  },
                  icon: Icon(
                      isDark
                          ? Icons.wb_sunny_outlined
                          : Icons.nights_stay_outlined,
                      color: theme.iconTheme.color),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                      (userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'U'),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Vertical bar chart widget centered inside the SectionCard
  Widget _verticalBarChart({
    required Map<String, int> data,
    required Map<String, String> labels,
    required List<Color> barColors,
    double height = 220,
  }) {
    final entries = data.entries.toList();
    final totalMax =
        entries.map((e) => e.value).fold<int>(0, (a, b) => a > b ? a : b);
    final maxValue = totalMax > 0 ? totalMax : 1;
    return LayoutBuilder(builder: (context, constraints) {
      final theme = Theme.of(context);
      final barCount = entries.length;
      final spacing = 12.0;
      final availableWidth = constraints.maxWidth;
      final barWidth = ((availableWidth - spacing * (barCount - 1)) / barCount)
          .clamp(32.0, 120.0);
      return SizedBox(
        height: height,
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: entries.map((e) {
                final label =
                    labels.containsKey(e.key) ? labels[e.key]! : e.key;
                final value = e.value;
                final pct = value / maxValue;
                final barHeight = (pct * (height - 48)).clamp(6.0, height - 48);
                final color =
                    barColors[(entries.indexOf(e)) % barColors.length];
                return Padding(
                  padding:
                      EdgeInsets.only(right: entries.last == e ? 0 : spacing),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(value.toString(), style: theme.textTheme.bodySmall),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: barWidth,
                        height: barHeight,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [
                                color.withOpacity(0.95),
                                color.withOpacity(0.7)
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: barWidth + 4,
                        child: Text(label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildContentBody(DashboardSummary summary, double contentWidth) {
    final theme = Theme.of(context);
    final ageLabels = {
      "20_30": "20–30",
      "31_40": "31–40",
      "41_50": "41–50",
      "51_55": "51–55",
      "56_60": "56–60",
      "61_plus": "61+",
    };
    final maritalLabels = {
      "unspecified": "Non spécifiée",
      "married": "Marié(e)",
      "single": "Célibataire",
      "divorced": "Divorcé(e)",
    };

    return RefreshIndicator(
      onRefresh: _loadSummary,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: _statCards(summary, theme, contentWidth)),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: SectionCard(
                title: "Répartition par âge",
                child: Center(
                  child: _verticalBarChart(
                    data: summary.ageDistribution
                        .map((k, v) => MapEntry(k, v as int)),
                    labels: ageLabels,
                    barColors: [Colors.blue.shade600, Colors.blue.shade600],
                    height: 220,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: SectionCard(
                title: "Situation matrimoniale",
                child: Center(
                  child: _verticalBarChart(
                    data: summary.maritalStatus
                        .map((k, v) => MapEntry(k, v as int)),
                    labels: maritalLabels,
                    barColors: [Colors.teal.shade600, Colors.teal.shade500],
                    height: 180,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: SectionCard(
                title: "Derniers arrivés",
                child: summary.recentPersonnel.isEmpty
                    ? _emptyPlaceholder(context, 'Aucun personnel récent',
                        icon: Icons.group)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children:
                            List.generate(summary.recentPersonnel.length, (i) {
                          final p = summary.recentPersonnel[i];
                          final name = (p['name'] ?? 'Inconnu').toString();
                          final subtitle =
                              (p['role'] ?? p['date'] ?? '').toString();
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                dense: false,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 8),
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: theme.colorScheme.primary
                                      .withOpacity(0.12),
                                  child: Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              color:
                                                  theme.colorScheme.primary)),
                                ),
                                title: Text(name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w700)),
                                subtitle: subtitle.isNotEmpty
                                    ? Text(subtitle,
                                        style: theme.textTheme.bodySmall)
                                    : null,
                                trailing: const Icon(Icons.chevron_right,
                                    color: Colors.grey),
                                onTap: () {/* open profile */},
                              ),
                              if (i < summary.recentPersonnel.length - 1)
                                const Divider(height: 1),
                            ],
                          );
                        }),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: SectionCard(
                title: "Anniversaires à venir",
                child: summary.upcomingBirthdays.isEmpty
                    ? _emptyPlaceholder(context, 'Aucun anniversaire à venir',
                        icon: Icons.cake)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                            summary.upcomingBirthdays.length, (i) {
                          final p = summary.upcomingBirthdays[i];
                          final name = (p['name'] ?? 'Inconnu').toString();
                          final date = (p['date'] ?? '').toString();
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                dense: false,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 8),
                                leading: const Icon(Icons.cake, size: 28),
                                title: Text(name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w700)),
                                subtitle: date.isNotEmpty
                                    ? Text(date,
                                        style: theme.textTheme.bodySmall)
                                    : null,
                                trailing: const Icon(Icons.chevron_right,
                                    color: Colors.grey),
                                onTap: () {/* open profile */},
                              ),
                              if (i < summary.upcomingBirthdays.length - 1)
                                const Divider(height: 1),
                            ],
                          );
                        }),
                      ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = _safeAuthState();
    if (auth != null && !auth.loggedIn) {
      if (_canUpdate) {
        Future.microtask(() {
          if (!mounted) return;
          try {
            context.go('/login');
          } catch (_) {}
        });
      }
    }

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Erreur: $_error",
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _loadSummary, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<DashboardSummary?>(
      future: _futureSummary,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Erreur: ${snapshot.error}",
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                      onPressed: _loadSummary, child: const Text('Réessayer')),
                ],
              ),
            ),
          );
        }

        final summary = snapshot.data!;
        final userEmail = auth?.userEmail ?? '';
        final theme = Theme.of(context);
        final ThemeNotifier? themeNotifier = ThemeNotifier.safeOf(context);

        // compute contentWidth consistent with header/search field and sections
        final screenWidth = MediaQuery.of(context).size.width;
        const horizontalPadding = 24.0;
        final sideNavWidth = (kIsWeb && screenWidth > 1400) ? 240.0 : 0.0;
        final contentAvailable =
            screenWidth - sideNavWidth - horizontalPadding * 2;
        final double contentWidth =
            contentAvailable > 1200 ? 1200 : contentAvailable;

        // Decide whether to hide the big header title:
        final bool hideHeaderTitle = screenWidth <= 480 || contentWidth < 520;

        // Footer: responsive
        final footer = Container(
          color: theme.colorScheme.surfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: LayoutBuilder(builder: (context, constraints) {
            return Row(
              children: [
                Expanded(
                  child: Text('© ${DateTime.now().year} BotaApp — Gestion RH',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.business, size: 16),
                          label: const Text('LinkedIn'),
                          style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12)),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.code, size: 16),
                          label: const Text('GitHub'),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        );

        final useFixedNav = kIsWeb || MediaQuery.of(context).size.width >= 900;
        final navExpanded =
            _navExpanded && (MediaQuery.of(context).size.width >= 1100);

        if (useFixedNav) {
          return Scaffold(
            bottomNavigationBar: footer,
            body: Row(
              children: [
                _sideNavExpanded(navExpanded, userEmail, theme),
                Expanded(
                  child: Column(
                    children: [
                      // Fixed header - pass hideHeaderTitle flag
                      _buildHeader(
                          contentWidth, theme, userEmail, hideHeaderTitle),
                      Expanded(child: _buildContentBody(summary, contentWidth)),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          // mobile / overlay navigation
          return Scaffold(
            bottomNavigationBar: footer,
            appBar: AppBar(
              title: LayoutBuilder(builder: (context, constraints) {
                if (hideHeaderTitle) return const SizedBox.shrink();
                final showLargeTitle = constraints.maxWidth >= 520;
                return Text('Tableau de bord RH',
                    style: showLargeTitle
                        ? theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)
                        : theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold));
              }),
              actions: [
                LayoutBuilder(builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 560;
                  if (narrow) {
                    final bool isDark = themeNotifier?.isDark ??
                        (theme.brightness == Brightness.dark);
                    return Row(children: [
                      IconButton(
                        onPressed: () {
                          if (!_canUpdate) return;
                          showModalBottomSheet(
                            context: context,
                            builder: (ctx) {
                              return Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _searchCtrl,
                                        autofocus: true,
                                        decoration: InputDecoration(
                                          hintText: 'Rechercher...',
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                          isDense: true,
                                        ),
                                        onSubmitted: (q) {
                                          Navigator.of(ctx).pop();
                                          if (!_canUpdate) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content:
                                                      Text('Recherche: $q')));
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(),
                                        icon: const Icon(Icons.close))
                                  ],
                                ),
                              );
                            },
                          );
                        },
                        icon: Icon(Icons.search,
                            color: Theme.of(context).iconTheme.color),
                      ),
                      PopupMenuButton<int>(
                        icon: Icon(Icons.more_vert,
                            color: Theme.of(context).iconTheme.color),
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                              value: 1,
                              child: ListTile(
                                  leading: Icon(Icons.notifications_none),
                                  title: Text('Notifications'))),
                          PopupMenuItem(
                              value: 2,
                              child: ListTile(
                                  leading: Icon(themeNotifier?.isDark ??
                                          (theme.brightness == Brightness.dark)
                                      ? Icons.wb_sunny_outlined
                                      : Icons.nights_stay_outlined),
                                  title: Text(themeNotifier?.isDark ??
                                          (theme.brightness == Brightness.dark)
                                      ? 'Passer en clair'
                                      : 'Passer en sombre'))),
                        ],
                        onSelected: (v) {
                          if (v == 2 && themeNotifier != null) {
                            if (!_canUpdate) return;
                            themeNotifier.toggle();
                          }
                        },
                      ),
                    ]);
                  } else {
                    return Row(
                      children: [
                        IconButton(
                            onPressed: () {},
                            icon: Icon(Icons.search,
                                color: Theme.of(context).iconTheme.color)),
                        IconButton(
                            onPressed: () {},
                            icon: Icon(Icons.notifications_none,
                                color: Theme.of(context).iconTheme.color)),
                        IconButton(
                          tooltip: themeNotifier?.isDark ??
                                  (theme.brightness == Brightness.dark)
                              ? 'Passer en clair'
                              : 'Passer en sombre',
                          onPressed: () {
                            if (!_canUpdate) return;
                            if (themeNotifier != null) themeNotifier.toggle();
                          },
                          icon: Icon(
                              themeNotifier?.isDark ??
                                      (theme.brightness == Brightness.dark)
                                  ? Icons.wb_sunny_outlined
                                  : Icons.nights_stay_outlined,
                              color: Theme.of(context).iconTheme.color),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: CircleAvatar(
                              backgroundColor: theme.colorScheme.primary,
                              child: Text(
                                  (userEmail.isNotEmpty
                                      ? userEmail[0].toUpperCase()
                                      : 'U'),
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: Colors.white))),
                        ),
                      ],
                    );
                  }
                }),
              ],
            ),
            drawer: Drawer(
                child:
                    SafeArea(child: _sideNavExpanded(true, userEmail, theme))),
            body: Column(
              children: [
                Expanded(child: _buildContentBody(summary, contentWidth)),
              ],
            ),
          );
        }
      },
    );
  }
}

/// Nav item with hover feedback (highlight + subtle translate) and tooltip when collapsed
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
    if (v) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isActive = widget.activeRoute == widget.route;
      final theme = Theme.of(context);
      const baseColor = Colors.white;
      final bgColor = isActive
          ? Colors.white.withOpacity(0.15)
          : (_hovering ? Colors.white.withOpacity(0.08) : Colors.transparent);

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
            child: inner,
          ),
        );
      }

      return MouseRegion(
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        cursor: SystemMouseCursors.click,
        child: inner,
      );
    });
  }
}
