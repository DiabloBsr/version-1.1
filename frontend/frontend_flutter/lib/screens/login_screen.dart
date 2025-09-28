import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../auth_provider.dart';
import '../utils/secure_storage.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    return regex.hasMatch(email);
  }

  Future<void> handleLogin() async {
    if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Email et mot de passe sont obligatoires")),
        );
      }
      return;
    }
    if (!_isValidEmail(emailCtrl.text.trim())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Email invalide")),
        );
      }
      return;
    }

    setState(() => loading = true);
    try {
      final response =
          await AuthService.login(emailCtrl.text.trim(), passCtrl.text);
      debugPrint('[Login] login response: $response');

      if (response['success'] == true) {
        final auth = AuthProvider.of(context);

        // Support multiple possible key names
        final access =
            (response['access'] as String?) ?? (response['access_token'] as String?);
        final refresh =
            (response['refresh'] as String?) ?? (response['refresh_token'] as String?);

        // Store tokens BEFORE doing profile fetch / navigation
        if (access != null && refresh != null) {
          debugPrint('[Login] saving tokens to AuthState');
          await auth.setTokens(access, refresh);

          // Debug: confirm stored token exists in secure storage
          final stored = await SecureStorage.read('access');
          debugPrint('[Login] SecureStorage access after setTokens: '
              '${stored != null ? stored.substring(0, 10) + "..." : "null"}');
        } else {
          debugPrint('[Login] login response contained no tokens');
        }

        // Récupération du profil (utilise tokens si présents)
        Map<String, dynamic>? profile;
        try {
          profile = await AuthService.getProfile();
          debugPrint('[Login] profile fetch result: $profile');
        } catch (e) {
          debugPrint('[Login] profile fetch error: $e');
        }

        // fallback values from storage
        final storedRole = await SecureStorage.read('role');
        final storedEmail = await SecureStorage.read('email');
        final storedMfa = await SecureStorage.read('mfa_enabled');
        final storedOtp = await SecureStorage.read('otp_verified');

        if (profile != null) {
          final role = (profile['role'] as String?) ?? storedRole;
          final email = (profile['user'] is Map)
              ? profile['user']['email'] as String?
              : storedEmail;
          final mfaEnabled = profile['mfa_enabled'] == true || storedMfa == 'true';
          final otp = profile['otp_verified'] == true ||
              profile['otp_verified'] == 'true' ||
              storedOtp == 'true';

          if (role != null) await auth.setRole(role);
          if (email != null) await auth.setUserEmail(email);
          await auth.setMfaEnabled(mfaEnabled);
          if (otp) await auth.setOtpVerified(true);
        } else {
          // Use stored values if profile not available
          if (storedRole != null) await auth.setRole(storedRole);
          if (storedEmail != null) await auth.setUserEmail(storedEmail);
          await auth.setMfaEnabled(storedMfa == 'true');
          if (storedOtp == 'true') await auth.setOtpVerified(true);
        }

        if (!mounted) return;

        // Redirection
        // Ensure loggedIn flag comes from setTokens; if not present, treat accordingly
        debugPrint(
            '[Login] auth.loggedIn=${auth.loggedIn}, otpVerified=${auth.otpVerified}, mfaEnabled=${auth.mfaEnabled}, role=${auth.role}');
        if (auth.loggedIn && auth.otpVerified) {
          final r = auth.role?.toLowerCase();
          if (r == 'admin') {
            context.go('/dashboard');
          } else if (r == 'user') {
            context.go('/user-home');
          } else {
            context.go('/home');
          }
        } else {
          if (auth.mfaEnabled == true) {
            context.go('/mfa-verify');
          } else {
            context.go('/mfa-setup');
          }
        }
      } else {
        String message = "Échec de connexion";
        if (response['error'] != null) {
          try {
            final error = jsonDecode(response['error']);
            if (error is Map && error.containsKey('detail')) {
              message = error['detail'];
            } else {
              message = error.toString();
            }
          } catch (_) {
            message = response['error'].toString();
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      }
    } catch (e, st) {
      debugPrint('[Login] unexpected error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur réseau: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connexion')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: loading ? null : handleLogin,
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Se connecter'),
            ),
            TextButton(
              onPressed: () => context.go('/register'),
              child: const Text("Créer un compte"),
            ),
          ],
        ),
      ),
    );
  }
}