import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth_state.dart';

import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/mfa_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mfa_setup_screen.dart';
import 'screens/mfa_verify_screen.dart';
import 'screens/dashboard_screen.dart';

GoRouter createRouter(AuthState authState) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: authState,
    redirect: (BuildContext context, GoRouterState state) {
      final loggedIn = authState.loggedIn;
      final path = state.uri.path;

      if (!loggedIn && path == '/dashboard') return '/login';
      if (loggedIn && path == '/login') return '/dashboard';

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/mfa', builder: (_, __) => const MFAScreen()),
      GoRoute(path: '/mfa-setup', builder: (_, __) => const MFASetupScreen()),
      GoRoute(path: '/mfa-verify', builder: (_, __) => const MFAVerifyScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
    ],
  );
}
