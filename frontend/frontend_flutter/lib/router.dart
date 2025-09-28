import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth_state.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/mfa_setup_screen.dart';
import 'screens/mfa_verify_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/user_home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/home_screen.dart';

GoRouter createRouter(AuthState authState) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authState,
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/mfa-setup', builder: (_, __) => const MFASetupScreen()),
      GoRoute(path: '/mfa-verify', builder: (_, __) => const MFAVerifyScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
      GoRoute(path: '/user-home', builder: (_, __) => const UserHomeScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    ],
    redirect: (context, state) {
      final uriPath = state.uri.path;
      final loggingIn = uriPath == '/login' || uriPath == '/register';

      debugPrint(
        'redirect called: loggedIn=${authState.loggedIn}, '
        'otpVerified=${authState.otpVerified}, '
        'mfaEnabled=${authState.mfaEnabled}, '
        'role=${authState.role}, '
        'uri=$uriPath',
      );

      // 1. Not logged in -> force login unless already there
      if (!authState.loggedIn && !loggingIn) {
        return '/login';
      }

      // 2. Logged in but MFA not verified -> force MFA unless already on MFA pages
      if (authState.loggedIn &&
          !authState.otpVerified &&
          uriPath != '/mfa-verify' &&
          uriPath != '/mfa-setup') {
        if (authState.mfaEnabled == true) return '/mfa-verify';
        return '/mfa-setup';
      }

      // 3. Logged in and MFA verified -> route by role
      if (authState.loggedIn && authState.otpVerified) {
        final role = authState.role?.toLowerCase();
        if (role == 'admin' && uriPath != '/dashboard') return '/dashboard';
        if (role == 'user' && uriPath != '/user-home') return '/user-home';
        if ((role == null || role.isEmpty) && uriPath != '/home')
          return '/home';
      }

      // 4. No redirect
      return null;
    },
  );
}
