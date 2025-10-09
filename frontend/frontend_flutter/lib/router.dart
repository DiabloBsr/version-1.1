// lib/router.dart
// ignore_for_file: unused_local_variable

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
import 'screens/bank_account_create_screen.dart';
import 'screens/bank_account_view_screen.dart';
import 'screens/bank_account_edit_screen.dart' as bank_edit;
import 'screens/history_screen.dart';
import 'services/auth_service.dart';

bool _isValidUuid(String id) {
  final uuidReg = RegExp(
      r'^[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}$');
  return uuidReg.hasMatch(id);
}

String _encodeNext(String next) => Uri.encodeComponent(next);

GoRouter createRouter(AuthState authState) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authState,
    routes: <GoRoute>[
      GoRoute(
          path: '/login',
          builder: (BuildContext context, GoRouterState state) =>
              const LoginScreen()),
      GoRoute(
          path: '/register',
          builder: (BuildContext context, GoRouterState state) =>
              const RegisterScreen()),
      GoRoute(
          path: '/profile-extra',
          builder: (BuildContext context, GoRouterState state) =>
              const ProfileExtraScreen()),
      GoRoute(
          path: '/mfa-setup',
          builder: (BuildContext context, GoRouterState state) =>
              const MFASetupScreen()),
      GoRoute(
          path: '/mfa-verify',
          builder: (BuildContext context, GoRouterState state) =>
              const MFAVerifyScreen()),
      GoRoute(
          path: '/home',
          builder: (BuildContext context, GoRouterState state) =>
              const HomeScreen()),
      GoRoute(
          path: '/dashboard',
          builder: (BuildContext context, GoRouterState state) =>
              const DashboardScreen()),
      GoRoute(
          path: '/user-home',
          builder: (BuildContext context, GoRouterState state) =>
              const UserHomeScreen()),
      GoRoute(
          path: '/profile',
          builder: (BuildContext context, GoRouterState state) =>
              const ProfileScreen()),
      GoRoute(
          path: '/profile/edit',
          builder: (BuildContext context, GoRouterState state) =>
              const ProfileEditScreen()),
      GoRoute(
          path: '/settings',
          builder: (BuildContext context, GoRouterState state) =>
              const SettingsScreen()),
      GoRoute(
          path: '/support',
          builder: (BuildContext context, GoRouterState state) =>
              const SupportScreen()),

      // Bank account routes
      GoRoute(
        path: '/bank-accounts',
        builder: (BuildContext context, GoRouterState state) =>
            const _BankAccountsRedirector(),
      ),

      GoRoute(
        path: '/bank-account/create',
        builder: (BuildContext context, GoRouterState state) =>
            const BankAccountCreateScreen(),
      ),

      GoRoute(
        path: '/bank-account/view/:id',
        builder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id'] ?? '';
          if (!_isValidUuid(id)) {
            return Scaffold(
              appBar: AppBar(title: const Text('Compte bancaire')),
              body: const Center(child: Text('Identifiant invalide')),
            );
          }
          return BankAccountViewScreen(id: id);
        },
      ),

      GoRoute(
        path: '/bank-account/edit/:id',
        builder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id'] ?? '';
          if (!_isValidUuid(id)) {
            return Scaffold(
              appBar: AppBar(title: const Text('Modifier le compte')),
              body: const Center(child: Text('Identifiant invalide')),
            );
          }
          return bank_edit.BankAccountEditScreen(id: id);
        },
      ),

      // History list route
      GoRoute(
          path: '/history',
          builder: (BuildContext context, GoRouterState state) =>
              const HistoryScreen()),
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

      // Authenticated routes patterns to allow without forcing role landing
      final allowedAuthenticatedPatterns = <Pattern>[
        RegExp(r'^/bank-account(/.*)?$'),
        RegExp(r'^/bank-accounts$'),
        RegExp(r'^/history(/.*)?$'),
        RegExp(r'^/profile(/.*)?$'),
        RegExp(r'^/settings(/.*)?$'),
        RegExp(r'^/support(/.*)?$'),
      ];

      bool matchesAllowedAuthenticated(String path) {
        for (final p in allowedAuthenticatedPatterns) {
          if (p is RegExp) {
            if (p.hasMatch(path)) return true;
          } else if (p is String) {
            if (p == path) return true;
          }
        }
        return false;
      }

      final bool ready = authState.initialized;
      final bool loggedInSync =
          ready && (authState.email != null && authState.email!.isNotEmpty);

      debugPrint(
        'redirect called: initialized=$ready, loggedInSync=$loggedInSync, '
        'otpVerified=${authState.otpVerified}, mfaEnabled=${authState.mfaEnabled}, '
        'pendingLogin=${authState.pendingLogin}, role=${authState.role}, uri=$uriPath',
      );

      if (!ready) return null;

      // If not logged in, force login and preserve next
      if (!loggedInSync && !onPublic) {
        final next = state.uri.toString();
        return '/login?next=${_encodeNext(next)}';
      }

      // If pending login (OTP expected) force mfa-verify and preserve next
      if (authState.pendingLogin == true && uriPath != '/mfa-verify') {
        final next = state.uri.toString();
        return '/mfa-verify?next=${_encodeNext(next)}';
      }

      // If logged in but not otpVerified, force MFA pages, preserve next
      if (loggedInSync &&
          !authState.otpVerified &&
          uriPath != '/mfa-verify' &&
          uriPath != '/mfa-setup') {
        final next = state.uri.toString();
        if (authState.mfaEnabled == true)
          return '/mfa-verify?next=${_encodeNext(next)}';
        return '/mfa-setup?next=${_encodeNext(next)}';
      }

      // If logged in and otpVerified, allow explicitly permitted authenticated routes
      if (loggedInSync && authState.otpVerified) {
        if (matchesAllowedAuthenticated(uriPath)) {
          // extra guard for view/edit id validity: if route is view/edit but id invalid, redirect to bank-accounts
          if (uriPath.startsWith('/bank-account/view/') ||
              uriPath.startsWith('/bank-account/edit/')) {
            final parts = uriPath.split('/');
            if (parts.length >= 4) {
              final id = parts[3];
              if (!_isValidUuid(id)) {
                return '/bank-accounts';
              }
            }
          }
          return null;
        }

        // Only apply role-based default landing if user is hitting a root/public landing ("/" or home)
        final bool isRootLike =
            uriPath == '/' || uriPath == '/home' || onPublic;
        if (isRootLike) {
          final role = authState.role?.toLowerCase();
          if (role == 'admin' && uriPath != '/dashboard') return '/dashboard';
          if (role == 'user' && uriPath != '/user-home') return '/user-home';
          if ((role == null || role.isEmpty) && uriPath != '/home')
            return '/home';
        }
      }

      return null;
    },
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      body: Center(child: Text('Erreur de navigation: ${state.error}')),
    ),
  );
}

/// Helper widget used for /bank-accounts route.
/// It checks whether the current user already has a bank account:
/// - if yes: navigates to /bank-account/view/<id>
/// - if no: navigates to /bank-account/create
/// While checking it displays a small loading indicator.
class _BankAccountsRedirector extends StatefulWidget {
  const _BankAccountsRedirector({Key? key}) : super(key: key);

  @override
  State<_BankAccountsRedirector> createState() =>
      _BankAccountsRedirectorState();
}

class _BankAccountsRedirectorState extends State<_BankAccountsRedirector> {
  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final profile = await AuthService.getProfile();
      // profile may be Map or null; handle both
      if (profile == null || profile.isEmpty) {
        if (mounted) context.go('/login');
        return;
      }

      // support multiple id keys and ensure string form
      final profileId = profile['id'] ?? profile['pk'] ?? profile['uuid'];
      if (profileId == null) {
        if (mounted) context.go('/bank-account/create');
        return;
      }

      final accounts =
          await AuthService.getBankAccounts(profileId: profileId.toString());
      if (!mounted) return;

      if (accounts != null && accounts.isNotEmpty) {
        final first = accounts.first;
        final id = first['id']?.toString();
        if (id != null && _isValidUuid(id)) {
          // navigate to view of existing account
          context.go('/bank-account/view/$id');
          return;
        }
      }

      // no account found -> go to create
      context.go('/bank-account/create');
    } catch (e, st) {
      debugPrint('[BankAccountsRedirector] error: $e\n$st');
      if (mounted) {
        // fallback to create screen on error
        context.go('/bank-account/create');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
