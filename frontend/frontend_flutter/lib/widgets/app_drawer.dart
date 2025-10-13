// lib/widgets/app_drawer.dart
// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../auth_provider.dart';
import '../services/auth_service.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.of(context);
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    // colors chosen from theme to ensure good contrast in both modes
    final headerBg =
        isDark ? theme.colorScheme.surfaceVariant : theme.colorScheme.primary;
    final headerText = isDark
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onPrimary;
    final headerSub = headerText.withOpacity(0.85);
    final avatarBg = isDark ? Colors.white12 : Colors.white24;
    final iconColor = theme.iconTheme.color;
    final dividerColor = theme.dividerColor;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: headerBg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: avatarBg,
                    child: Icon(Icons.person, color: headerText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.userEmail ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: headerText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          auth.role ?? 'Utilisateur',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: headerSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Use ListTileTheme so icons and text follow theme colors and contrast rules
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTileTheme(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    iconColor: iconColor,
                    textColor: theme.textTheme.bodyLarge?.color,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.home),
                          title: const Text('Accueil'),
                          onTap: () {
                            Navigator.of(context).pop();
                            context.go('/home');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.dashboard),
                          title: const Text('Tableau de bord'),
                          onTap: () {
                            Navigator.of(context).pop();
                            context.go('/dashboard');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.people),
                          title: const Text('Personnel'),
                          onTap: () {
                            Navigator.of(context).pop();
                            context.go('/personnel');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.cake),
                          title: const Text('Anniversaires'),
                          onTap: () {
                            Navigator.of(context).pop();
                            context.go('/birthdays');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.person),
                          title: const Text('Profil'),
                          onTap: () {
                            Navigator.of(context).pop();
                            context.go('/profile');
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: ListTileTheme(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                iconColor: iconColor,
                textColor: theme.textTheme.bodyLarge?.color,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Se déconnecter'),
                      onTap: () async {
                        Navigator.of(context).pop();
                        try {
                          await AuthService.logout();
                        } catch (_) {}
                        final authState = AuthProvider.of(context);
                        await authState.clearAll();
                        context.go('/login');
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
