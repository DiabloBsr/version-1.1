import 'package:flutter/material.dart';

class UserHomeScreen extends StatelessWidget {
  const UserHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Accueil Utilisateur")),
      body: const Center(
        child: Text("Bienvenue sur le Home utilisateur 👤"),
      ),
    );
  }
}
