import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../widgets/app_drawer.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _email = TextEditingController();
  File? _image;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await AuthService.getProfile();
    if (profile != null) {
      // adapte les clés selon la réponse de ton backend
      _nom.text = (profile['nom'] ?? profile['first_name'] ?? '') as String;
      _prenom.text =
          (profile['prenom'] ?? profile['last_name'] ?? '') as String;
      _email.text = (profile['email'] ?? '') as String;
      setState(() {});
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final res =
        await picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
    if (res != null) setState(() => _image = File(res.path));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final success = await AuthService.updateProfile(
      nom: _nom.text.trim(),
      prenom: _prenom.text.trim(),
      email: _email.text.trim(),
      photoFile: _image,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (success == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profil mis à jour')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Échec mise à jour'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      drawer: const AppDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 48,
                  child: _image == null ? const Icon(Icons.camera_alt) : null,
                  backgroundImage: _image != null ? FileImage(_image!) : null,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nom,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
              ),
              TextFormField(
                controller: _prenom,
                decoration: const InputDecoration(labelText: 'Prénom'),
                validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
              ),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requis';
                  final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                  if (!regex.hasMatch(v)) return 'Email invalide';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
