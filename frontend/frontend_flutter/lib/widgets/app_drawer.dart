import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../auth_provider.dart';
import '../services/auth_service.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Compact header: avatar + email + role (no big title)
            Container(
              width: double.infinity,
              color: Colors.blue.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white24,
                    child: const Icon(Icons.person, color: Colors.white),
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
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          auth.role ?? 'Utilisateur',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Navigation items
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

            const Spacer(),
            const Divider(height: 1),
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
          ],
        ),
      ),
    );
  }
}
