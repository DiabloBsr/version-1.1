// lib/screens/dashboard_screen.dart
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

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _error = null;
      _futureSummary = null;
    });

    final access = await SecureStorage.read('access');
    if (access == null || access.isEmpty) {
      setState(() {
        _error = 'Token manquant. Veuillez vous reconnecter.';
        _loading = false;
      });
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) context.go('/login');
      });
      return;
    }

    try {
      final data = await _service.fetchDashboardSummary();
      final summary = DashboardSummary.fromJson(data);
      setState(() {
        _futureSummary = Future.value(summary);
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('[Dashboard] fetch error: $e\n$st');

      final refreshed = await AuthService.refreshTokens();
      if (refreshed) {
        if (mounted) return _loadSummary();
      }

      try {
        final auth = AuthProvider.of(context);
        await auth.clearAll();
      } catch (_) {}

      setState(() {
        _error = e.toString();
        _loading = false;
      });

      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) context.go('/login');
      });
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
    setState(() => _activeRoute = route);
    if (!kIsWeb) Navigator.pop(context);
    context.go(route);
  }

  Widget _sideNav(bool expanded, String userEmail, ThemeData theme) {
    final effectiveWidth = expanded ? 220.0 : 72.0;
    return Container(
      width: effectiveWidth,
      color: Colors.blue.shade800,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 14 : 8, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                        color: Colors.white24, shape: BoxShape.circle),
                    child: const Icon(Icons.business,
                        color: Colors.white, size: 24),
                  ),
                  if (expanded)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('BotaApp',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(userEmail,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 6),
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
                  horizontal: expanded ? 12 : 6, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white10,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    try {
                      final auth = AuthProvider.of(context);
                      await auth.clearAll();
                    } catch (_) {}
                    context.go('/login');
                  },
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Expanded(
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
      DashboardSummary summary, ThemeData theme, double maxWidth) {
    final cards = [
      _StatCard(
        title: "Total utilisateurs",
        value: summary.totalUsers.toString(),
        color: theme.colorScheme.primary,
        icon: Icons.people,
      ),
      _StatCard(
        title: "Personnel actif",
        value: summary.activePersonnel.toString(),
        color: Colors.green,
        icon: Icons.check_circle,
      ),
      _StatCard(
        title: "Nouveaux ce mois",
        value: summary.newThisMonth.toString(),
        color: Colors.orange,
        icon: Icons.add,
      ),
    ];

    final int columns = maxWidth >= 1400
        ? 4
        : (maxWidth >= 1100 ? 3 : (maxWidth >= 800 ? 2 : 1));

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 4.0,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget _buildContent(DashboardSummary summary) {
    final theme = Theme.of(context);

    final ageLabels = {
      "20_30": "0–30",
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

    final gradientColors = [
      const Color.fromARGB(255, 47, 151, 193),
      const Color.fromARGB(255, 24, 40, 145),
      const Color.fromARGB(255, 1, 22, 43),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width:
                    width > 900 ? 340 : (width > 600 ? 300 : double.infinity),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.search,
                            color: theme.iconTheme.color?.withOpacity(0.9),
                            size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            style: theme.textTheme.bodyMedium,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Rechercher...',
                              hintStyle: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.5)),
                            ),
                            onSubmitted: (q) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Recherche: $q')));
                            },
                          ),
                        ),
                        IconButton(
                            onPressed: () {},
                            icon: Icon(Icons.filter_list,
                                color: theme.iconTheme.color)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _statCards(summary, theme, width),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: width > 1100 ? 2 : 1,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _SectionCard(
                  title: "Répartition par âge",
                  data: summary.ageDistribution
                      .map((k, v) => MapEntry(k, v as int)),
                  labels: ageLabels,
                  gradientColors: gradientColors,
                ),
                _SectionCard(
                  title: "Situation matrimoniale",
                  data: summary.maritalStatus
                      .map((k, v) => MapEntry(k, v as int)),
                  labels: maritalLabels,
                  gradientColors: gradientColors,
                ),
                _SectionCardList(
                  title: "Derniers arrivés",
                  items: summary.recentPersonnel,
                ),
                _SectionCardList(
                  title: "Anniversaires à venir",
                  items: summary.upcomingBirthdays,
                  leadingIcon: Icons.cake,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = _safeAuthState();
    if (auth != null && !auth.loggedIn) {
      Future.microtask(() => context.go('/login'));
    }

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
          body: Center(
              child: Text("Erreur: $_error",
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))));
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
                  child: Text("Erreur: ${snapshot.error}",
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))));
        }

        final summary = snapshot.data!;
        final userEmail = auth?.userEmail ?? '';
        final theme = Theme.of(context);
        final themeNotifier = ThemeProvider.safeOf(context);

        final footer = Container(
          color: theme.scaffoldBackgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                  child: Text('© ${DateTime.now().year} BotaApp — Gestion RH',
                      style: theme.textTheme.bodyMedium)),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.business,
                        size: 16, color: Colors.white),
                    label: const Text('LinkedIn',
                        style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A66C2)),
                  ),
                  OutlinedButton.icon(
                      onPressed: () {},
                      icon: Icon(Icons.code, color: theme.iconTheme.color),
                      label: Text('GitHub', style: theme.textTheme.bodySmall)),
                ],
              ),
            ],
          ),
        );

        return LayoutBuilder(builder: (context, constraints) {
          final useFixedNav = kIsWeb || constraints.maxWidth >= 900;
          final navExpanded = _navExpanded && (constraints.maxWidth >= 1100);

          if (useFixedNav) {
            return Scaffold(
              bottomNavigationBar: footer,
              body: Row(
                children: [
                  _sideNav(navExpanded, userEmail, theme),
                  Expanded(
                    child: Column(
                      children: [
                        Material(
                          elevation: 2,
                          child: Container(
                            height: 64,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const SizedBox(width: 24),
                                Expanded(
                                    child: Center(
                                        child: Text('Tableau de bord RH',
                                            style:
                                                theme.textTheme.titleLarge))),
                                Row(
                                  children: [
                                    IconButton(
                                        onPressed: () {},
                                        icon: Icon(Icons.notifications_none,
                                            color: theme.iconTheme.color)),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: themeNotifier.isDark
                                          ? 'Passer en clair'
                                          : 'Passer en sombre',
                                      onPressed: () => themeNotifier.toggle(),
                                      icon: Icon(
                                          themeNotifier.isDark
                                              ? Icons.wb_sunny_outlined
                                              : Icons.nights_stay_outlined,
                                          color: theme.iconTheme.color),
                                    ),
                                    const SizedBox(width: 8),
                                    CircleAvatar(
                                        child: Text(
                                            (userEmail.isNotEmpty
                                                ? userEmail[0].toUpperCase()
                                                : 'U'),
                                            style: theme.textTheme.bodyMedium)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(child: _buildContent(summary)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          } else {
            return Scaffold(
              bottomNavigationBar: footer,
              appBar: AppBar(
                title: Text('Tableau de bord RH',
                    style: theme.textTheme.titleLarge),
                actions: [
                  IconButton(
                      onPressed: () {},
                      icon: Icon(Icons.notifications_none,
                          color: theme.iconTheme.color)),
                  IconButton(
                    onPressed: () => themeNotifier.toggle(),
                    icon: Icon(
                        themeNotifier.isDark
                            ? Icons.wb_sunny_outlined
                            : Icons.nights_stay_outlined,
                        color: theme.iconTheme.color),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: CircleAvatar(
                        child: Text(
                            (userEmail.isNotEmpty
                                ? userEmail[0].toUpperCase()
                                : 'U'),
                            style: theme.textTheme.bodyMedium)),
                  ),
                ],
              ),
              drawer: null,
              body: _buildContent(summary),
            );
          }
        });
      },
    );
  }
}

/// Nav item with hover feedback (highlight + subtle translate)
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

class _HoverNavItemState extends State<_HoverNavItem> {
  bool _hovering = false;

  void _setHover(bool v) {
    if (mounted) setState(() => _hovering = v);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.activeRoute == widget.route;
    Theme.of(context);
    const baseColor = Colors.white;
    final bgColor = isActive
        ? Colors.white.withOpacity(0.10)
        : (_hovering ? Colors.white.withOpacity(0.06) : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        padding: EdgeInsets.symmetric(
            horizontal: widget.expanded ? 12 : 8, vertical: 8),
        decoration: BoxDecoration(
            color: bgColor, borderRadius: BorderRadius.circular(8)),
        child: InkWell(
          onTap: () => widget.onTap(widget.route),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 36,
                width: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white24
                      : (_hovering ? Colors.white12 : Colors.transparent),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: baseColor, size: 20),
              ),
              if (widget.expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: TextStyle(
                        color: baseColor,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w600),
                    child: Text(widget.label),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small self-contained StatCard that respects theme colors
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData? icon;

  const _StatCard(
      {required this.title,
      required this.value,
      required this.color,
      this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.85));
    final valueStyle = theme.textTheme.titleLarge
        ?.copyWith(color: color, fontWeight: FontWeight.w800, fontSize: 18);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (icon != null)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 20),
              ),
            if (icon != null) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text(value, style: valueStyle),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: theme.iconTheme.color?.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}

/// Section card that shows distribution with counts and percents
class _SectionCard extends StatelessWidget {
  final String title;
  final Map<String, int> data;
  final Map<String, String>? labels;
  final List<Color> gradientColors;

  const _SectionCard(
      {required this.title,
      required this.data,
      required this.gradientColors,
      this.labels});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = data.values.fold<int>(0, (a, b) => a + b);
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          Column(
            children: entries.map((e) {
              final label = labels != null && labels!.containsKey(e.key)
                  ? labels![e.key]!
                  : e.key;
              final count = e.value;
              final pct = total > 0 ? count / total : 0.0;
              final pctText = '${(pct * 100).round()}%';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                        width: 120,
                        child: Text(label, style: theme.textTheme.bodyMedium)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(builder: (ctx, constraints) {
                        final full = constraints.maxWidth;
                        final width = (pct * full).clamp(4.0, full);
                        final gradient = LinearGradient(
                            colors: gradientColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight);
                        return Stack(children: [
                          Container(
                              height: 14,
                              decoration: BoxDecoration(
                                  color: theme.colorScheme.surface
                                      .withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(8))),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: (width / full).isFinite
                                  ? (width / full)
                                  : 0.0,
                              child: Container(
                                  height: 14,
                                  width: full,
                                  decoration:
                                      BoxDecoration(gradient: gradient)),
                            ),
                          ),
                        ]);
                      }),
                    ),
                    const SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(count.toString(),
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text(pctText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.65))),
                        ]),
                  ],
                ),
              );
            }).toList(),
          ),
        ]),
      ),
    );
  }
}

/// Section showing a simple list (recent personnel / birthdays)
class _SectionCardList extends StatelessWidget {
  final String title;
  final List<dynamic> items;
  final IconData? leadingIcon;

  const _SectionCardList(
      {required this.title, required this.items, this.leadingIcon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Column(
            children: items.map((p) {
              final name = p['name'] ?? 'Inconnu';
              final subtitle = p['role'] ?? p['date'] ?? '';
              final trailing = p['email'] ?? p['joined'] ?? '';
              return ListTile(
                dense: true,
                leading: leadingIcon != null
                    ? Icon(leadingIcon, color: theme.colorScheme.secondary)
                    : CircleAvatar(
                        child: Text(name[0].toUpperCase(),
                            style: theme.textTheme.bodyMedium)),
                title: Text(name, style: theme.textTheme.bodyMedium),
                subtitle: subtitle != ''
                    ? Text(subtitle, style: theme.textTheme.bodySmall)
                    : null,
                trailing: Text(trailing, style: theme.textTheme.bodySmall),
              );
            }).toList(),
          ),
        ]),
      ),
    );
  }
}
