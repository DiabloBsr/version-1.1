// lib/main.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'auth_state.dart';
import 'auth_provider.dart';
import 'router.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize app version for UI
  try {
    final info = await PackageInfo.fromPlatform();
    AuthService.appVersion = '${info.version}+${info.buildNumber}';
  } catch (_) {
    AuthService.appVersion = null;
  }

  final authState = AuthState();
  await authState.initFromStorage();

  if (authState.loggedIn) {
    debugPrint(
        '[main] detected loggedIn=true on startup, attempting silent refresh');
    final refreshed = await AuthService.refreshTokens();
    if (!refreshed) {
      debugPrint(
          '[main] silent refresh failed — clearing authState before app start');
      await authState.clearAll();
    } else {
      debugPrint('[main] silent refresh succeeded');
    }
  }

  final router = createRouter(authState);

  runApp(
    AuthProvider(
      authState: authState,
      child: MyApp(router: router),
    ),
  );
}

class MyApp extends StatelessWidget {
  final GoRouter router;
  const MyApp({required this.router, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HR App',
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,

      // LIGHT THEME
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A66C2),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 1,
          iconTheme: IconThemeData(color: Colors.black87),
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: Colors.black87,
              displayColor: Colors.black87,
            ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),

      // DARK THEME
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A66C2),
          brightness: Brightness.dark,
        ).copyWith(
          background: const Color(0xFF0B1220),
          surface: const Color(0xFF0E1724),
          onBackground: Colors.white70,
          onSurface: Colors.white70,
          onPrimary: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF081426),
          foregroundColor: Colors.white,
          elevation: 1,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white70,
              displayColor: Colors.white,
            ),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
    );
  }
}
