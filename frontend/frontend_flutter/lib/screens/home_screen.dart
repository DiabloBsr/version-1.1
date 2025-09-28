import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../auth_provider.dart';
import '../services/auth_service.dart';
import '../widgets/app_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loggingOut = false;

  // Utilisé depuis UI (bouton de déconnexion).
  // Protège l'utilisation de BuildContext après un await avec mounted checks.
  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);

    try {
      await AuthService.logout();
    } catch (_) {
      // ignore or log if desired
    }

    if (!mounted) return;

    final auth = AuthProvider.of(context);
    await auth.clearAll();

    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
        actions: [
          IconButton(
            tooltip: 'Profil',
            icon: const Icon(Icons.person),
            onPressed: () => context.go('/profile'),
          ),
          IconButton(
            tooltip: 'Déconnexion',
            icon: _loggingOut
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.logout),
            onPressed: _loggingOut ? null : _logout,
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: const Center(
        child: Text('Bienvenue'),
      ),
    );
  }
}
