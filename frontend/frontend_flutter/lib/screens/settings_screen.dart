// lib/screens/settings_screen.dart
import 'dart:io'
    show File; // File n'existe pas sur web, mais on le garde pour mobile
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/user_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  File? _profileImage; // utilisé sur mobile
  Uint8List? _webImage; // utilisé sur web
  bool _mfaEnabled = false;

  /// Sélection d'une image (web ou mobile)
  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        if (kIsWeb) {
          // Sur web, on lit les bytes directement
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _webImage = bytes;
            _profileImage = null;
          });
          await UserService.uploadProfilePhotoWeb(bytes);
        } else {
          // Sur mobile, on utilise File
          final file = File(pickedFile.path);
          setState(() {
            _profileImage = file;
            _webImage = null;
          });
          await UserService.uploadProfilePhoto(file);
        }
        _showSnack("Photo mise à jour avec succès");
      }
    } catch (e) {
      _showSnack("Erreur lors de l'upload: $e");
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- Dialogues pour infos, mot de passe, MFA (inchangés) ---
  Future<void> _editInfoDialog() async {
    final nom = TextEditingController();
    final prenom = TextEditingController();
    final email = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Modifier mes informations"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nom,
                decoration: const InputDecoration(labelText: "Nom")),
            TextField(
                controller: prenom,
                decoration: const InputDecoration(labelText: "Prénom")),
            TextField(
                controller: email,
                decoration: const InputDecoration(labelText: "Email")),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Enregistrer")),
        ],
      ),
    );

    if (ok == true) {
      try {
        await UserService.updateProfile({
          "nom": nom.text,
          "prenom": prenom.text,
          "user": {"email": email.text}
        });
        _showSnack("Informations mises à jour");
      } catch (e) {
        _showSnack("Erreur: $e");
      }
    }
  }

  Future<void> _changePasswordDialog() async {
    final oldPwd = TextEditingController();
    final newPwd = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Changer le mot de passe"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: oldPwd,
                decoration:
                    const InputDecoration(labelText: "Ancien mot de passe"),
                obscureText: true),
            TextField(
                controller: newPwd,
                decoration:
                    const InputDecoration(labelText: "Nouveau mot de passe"),
                obscureText: true),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Changer")),
        ],
      ),
    );

    if (ok == true) {
      try {
        await UserService.changePassword(oldPwd.text, newPwd.text);
        _showSnack("Mot de passe mis à jour");
      } catch (e) {
        _showSnack("Erreur: $e");
      }
    }
  }

  Future<void> _toggleMFA(bool val) async {
    try {
      await UserService.setMFA(enabled: val);
      setState(() => _mfaEnabled = val);
      _showSnack("MFA ${val ? 'activé' : 'désactivé'}");
    } catch (e) {
      _showSnack("Erreur MFA: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatar;
    if (_profileImage != null) {
      avatar = FileImage(_profileImage!);
    } else if (_webImage != null) {
      avatar = MemoryImage(_webImage!);
    } else {
      avatar = const AssetImage("assets/profile_placeholder.png");
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Paramètres")),
      body: ListView(
        children: [
          // --- Profil utilisateur avec photo ---
          Center(
            child: Column(
              children: [
                const SizedBox(height: 20),
                CircleAvatar(radius: 50, backgroundImage: avatar),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text("Changer la photo"),
                ),
              ],
            ),
          ),
          const Divider(),

          // --- Informations utilisateur ---
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text("Modifier mes informations"),
            onTap: _editInfoDialog,
          ),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text("Changer le mot de passe"),
            onTap: _changePasswordDialog,
          ),
          const Divider(),

          // --- Sécurité ---
          const Padding(
            padding: EdgeInsets.all(12.0),
            child: Text("Sécurité",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          SwitchListTile(
            title: const Text("Activer OTP"),
            subtitle: const Text("Authentification à deux facteurs"),
            value: _mfaEnabled,
            onChanged: _toggleMFA,
          ),
          const Divider(),

          // --- Préférences ---
          const Padding(
            padding: EdgeInsets.all(12.0),
            child: Text("Préférences",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text("Langue"),
            subtitle: const Text("Français"),
            onTap: () => _showSnack("Sélecteur de langue à implémenter"),
          ),
          SwitchListTile(
            title: const Text("Mode sombre"),
            value: false,
            onChanged: (val) => _showSnack("Mode sombre à implémenter"),
          ),
          SwitchListTile(
            title: const Text("Notifications"),
            value: true,
            onChanged: (val) => _showSnack("Notifications à implémenter"),
          ),
          const Divider(),

          // --- Support ---
          ListTile(
            leading: const Icon(Icons.feedback),
            title: const Text("Envoyer une suggestion"),
            onTap: () => _showSnack("Formulaire de feedback à implémenter"),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Déconnexion"),
            onTap: () => _showSnack("Déconnexion à implémenter"),
          ),
        ],
      ),
    );
  }
}
