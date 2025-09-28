import 'package:flutter/material.dart';
import 'router.dart';
import 'utils/secure_storage.dart';
import 'auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authState = AuthState();
  final token = await SecureStorage.read("access_token");
  authState.setLoggedIn(token != null && token.isNotEmpty);

  runApp(BotaApp(authState: authState));
}

class BotaApp extends StatelessWidget {
  final AuthState authState;
  const BotaApp({super.key, required this.authState});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Bota RH',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        // ✅ soit tu enlèves complètement cardTheme
        // ✅ soit tu utilises CardThemeData si tu veux garder un style global
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        ),
      ),
      routerConfig: createRouter(authState),
    );
  }
}
