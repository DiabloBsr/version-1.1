import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import 'dart:convert';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Email et mot de passe sont obligatoires")),
      );
      return;
    }
    if (!_isValidEmail(emailCtrl.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email invalide")),
      );
      return;
    }

    setState(() => loading = true);
    try {
      final response = await AuthService.login(emailCtrl.text, passCtrl.text);
      setState(() => loading = false);

      if (response['success'] == true) {
        // ✅ Vérifier le profil utilisateur pour savoir si MFA est activé
        final profile = await AuthService.getProfile();
        if (profile != null && profile['mfa_enabled'] == true) {
          context.go('/mfa'); // Aller à l’écran de saisie OTP
        } else {
          context.go('/mfa-setup'); // Aller à l’écran QR code
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur réseau: $e')),
      );
    }
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
                  ? const CircularProgressIndicator()
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
