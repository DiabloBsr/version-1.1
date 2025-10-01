// lib/router.dart
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
import 'screens/profile_extra_screen.dart';
import 'screens/profile_edit_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/support_screen.dart';

GoRouter createRouter(AuthState authState) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authState,
    routes: <GoRoute>[
      GoRoute(
        path: '/login',
        builder: (BuildContext context, GoRouterState state) =>
            const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (BuildContext context, GoRouterState state) =>
            const RegisterScreen(),
      ),
      GoRoute(
        path: '/profile-extra',
        builder: (BuildContext context, GoRouterState state) =>
            const ProfileExtraScreen(),
      ),
      GoRoute(
        path: '/mfa-setup',
        builder: (BuildContext context, GoRouterState state) =>
            const MFASetupScreen(),
      ),
      GoRoute(
        path: '/mfa-verify',
        builder: (BuildContext context, GoRouterState state) =>
            const MFAVerifyScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (BuildContext context, GoRouterState state) =>
            const HomeScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (BuildContext context, GoRouterState state) =>
            const DashboardScreen(),
      ),
      GoRoute(
        path: '/user-home',
        builder: (BuildContext context, GoRouterState state) =>
            const UserHomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (BuildContext context, GoRouterState state) =>
            const ProfileScreen(),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (BuildContext context, GoRouterState state) =>
            const ProfileEditScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
      ),
      GoRoute(
        path: '/support',
        builder: (BuildContext context, GoRouterState state) =>
            const SupportScreen(),
      ),
    ],
    redirect: (BuildContext context, GoRouterState state) {
      final uriPath = state.uri.path;

      final basePublicPaths = {
        '/login',
        '/register',
        '/profile-extra',
        '/support',
      };

      final dynamicPublicPaths = Set<String>.from(basePublicPaths);
      if (authState.pendingLogin == true) {
        dynamicPublicPaths.add('/mfa-verify');
      }

      final onPublic = dynamicPublicPaths.contains(uriPath);

      // Use initialized + email presence as a safe synchronous indicator to avoid redirect loops
      final bool ready = authState.initialized;
      final bool loggedInSync =
          ready && (authState.email != null && authState.email!.isNotEmpty);

      debugPrint(
        'redirect called: initialized=$ready, loggedInSync=$loggedInSync, '
        'otpVerified=${authState.otpVerified}, mfaEnabled=${authState.mfaEnabled}, '
        'pendingLogin=${authState.pendingLogin}, role=${authState.role}, uri=$uriPath',
      );

      // If AuthState still initializing, don't force navigation (let UI decide)
      if (!ready) return null;

      // 1. Not logged in -> allow public pages (including mfa-verify if pending), otherwise force login
      if (!loggedInSync && !onPublic) {
        return '/login';
      }

      // 2. Pending login (OTP expected) -> force /mfa-verify
      if (authState.pendingLogin == true && uriPath != '/mfa-verify') {
        return '/mfa-verify';
      }

      // 3. Logged in but MFA not verified -> force MFA pages
      if (loggedInSync &&
          !authState.otpVerified &&
          uriPath != '/mfa-verify' &&
          uriPath != '/mfa-setup') {
        if (authState.mfaEnabled == true) return '/mfa-verify';
        return '/mfa-setup';
      }

      // Allow profile-related routes when authenticated and MFA verified
      final bool isProfileRoute = uriPath == '/profile' ||
          uriPath == '/profile/edit' ||
          uriPath.startsWith('/profile/');
      if (loggedInSync && authState.otpVerified && isProfileRoute) return null;

      // 4. Logged in and MFA verified -> route by role (default landing)
      if (loggedInSync && authState.otpVerified) {
        final role = authState.role?.toLowerCase();
        if (role == 'admin' && uriPath != '/dashboard') return '/dashboard';
        if (role == 'user' && uriPath != '/user-home') return '/user-home';
        if ((role == null || role.isEmpty) && uriPath != '/home')
          return '/home';
      }

      // 5. No redirect required
      return null;
    },
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      body: Center(child: Text('Erreur de navigation: ${state.error}')),
    ),
  );
}
