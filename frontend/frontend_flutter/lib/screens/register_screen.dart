import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final emailCtrl = TextEditingController();
  final usernameCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final firstCtrl = TextEditingController();
  final lastCtrl = TextEditingController();
  bool loading = false;

  /// Vérifie que l'email est valide
  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    return regex.hasMatch(email);
  }

  /// Vérifie que le mot de passe est fort
  bool _isStrongPassword(String password) {
    return password.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password) &&
        RegExp(r'[!@#\$&*~]').hasMatch(password);
  }

  Future<void> handleRegister() async {
    // Validation côté client
    if (emailCtrl.text.isEmpty ||
        usernameCtrl.text.isEmpty ||
        passCtrl.text.isEmpty ||
        firstCtrl.text.isEmpty ||
        lastCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tous les champs sont obligatoires")),
      );
      return;
    }
    if (!_isValidEmail(emailCtrl.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email invalide")),
      );
      return;
    }
    if (!_isStrongPassword(passCtrl.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Mot de passe trop faible (min 8 caractères, 1 majuscule, 1 chiffre, 1 symbole)")),
      );
      return;
    }

    setState(() => loading = true);
    try {
      final res = await http
          .post(
            Uri.parse('http://127.0.0.1:8000/api/v1/auth/users/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': emailCtrl.text,
              'username': usernameCtrl.text,
              'password': passCtrl.text,
              'first_name': firstCtrl.text,
              'last_name': lastCtrl.text,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 201 || res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compte créé avec succès ✅')),
        );
        context.go('/login');
      } else {
        final error = jsonDecode(res.body);
        String message = "Erreur inconnue";
        if (error is Map) {
          if (error.containsKey('email')) {
            message = "Cet email est déjà utilisé";
          } else if (error.containsKey('username')) {
            message = "Ce nom d’utilisateur est déjà pris";
          } else if (error.containsKey('password')) {
            message = "Mot de passe invalide : ${error['password']}";
          } else {
            message = error.toString();
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec de connexion: $e')),
      );
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inscription')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: usernameCtrl,
              decoration: const InputDecoration(labelText: 'Nom d’utilisateur'),
            ),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe'),
            ),
            TextField(
              controller: firstCtrl,
              decoration: const InputDecoration(labelText: 'Prénom'),
            ),
            TextField(
              controller: lastCtrl,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: loading ? null : handleRegister,
              child: loading
                  ? const CircularProgressIndicator()
                  : const Text('Créer le compte'),
            ),
          ],
        ),
      ),
    );
  }
}
