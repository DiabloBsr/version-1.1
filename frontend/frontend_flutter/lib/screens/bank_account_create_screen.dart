// lib/screens/bank_account_create_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';

class BankAccountCreateScreen extends StatefulWidget {
  const BankAccountCreateScreen({Key? key}) : super(key: key);

  @override
  State<BankAccountCreateScreen> createState() =>
      _BankAccountCreateScreenState();
}

class _BankAccountCreateScreenState extends State<BankAccountCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bankNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _ibanCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _currency = 'MAD';
  bool _isPrimary = true;

  bool _submitting = false;
  bool _loadingProfile = true;
  String? _profileId;
  String? _profileUsername; // shown as titulaire (read-only)

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _ibanCtrl.dispose();
    _branchCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() => _loadingProfile = true);
    try {
      final profile = await AuthService.getProfile();
      if (profile == null) {
        if (!mounted) return;
        context.go('/login');
        return;
      }

      final id = profile['id'] ?? profile['pk'] ?? profile['uuid'];
      if (id != null) _profileId = id.toString();

      // Prefer explicit username fields; fall back to common alternatives
      String? username;
      if (profile['user'] is Map) {
        final user = profile['user'] as Map;
        username = (user['username'] ?? user['handle'] ?? user['display_name'])
            ?.toString();
      }
      username ??=
          (profile['username'] ?? profile['handle'] ?? profile['display_name'])
              ?.toString();
      // last fallback: email local part (but your request says username preferred; keep fallback minimal)
      if ((username == null || username.isEmpty) &&
          profile['email'] is String) {
        final email = profile['email'] as String;
        if (email.contains('@')) username = email.split('@').first;
      }

      _profileUsername = username ?? 'Utilisateur';
    } catch (e) {
      debugPrint('[BankAccountCreate] loadProfile error: $e');
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_profileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil utilisateur introuvable')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final payload = {
        'bank_name': _bankNameCtrl.text.trim(),
        // set owner_name to username (read-only display)
        'owner_name': _profileUsername ?? '',
        'account_number': _accountNumberCtrl.text.trim(),
        'iban': _ibanCtrl.text.trim(),
        'branch_name': _branchCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
        'is_primary': _isPrimary,
        'currency': _currency,
        'profile': _profileId,
      };

      final resp = await AuthService.createBankAccount(payload);
      if (resp != null && resp['id'] != null) {
        if (!mounted) return;
        context.go('/bank-account/view/${resp['id']}');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Erreur création compte. Vérifier les champs et réessayer.')),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter compte bancaire')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loadingProfile
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _bankNameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Nom de la banque'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Requis' : null,
                      ),
                      const SizedBox(height: 12),

                      // Titulaire: display-only showing username
                      TextFormField(
                        initialValue: _profileUsername ?? '',
                        decoration:
                            const InputDecoration(labelText: 'Titulaire'),
                        enabled: false,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _accountNumberCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Numéro de compte'),
                        keyboardType: TextInputType.text,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Requis';
                          if (v.trim().length < 6) return 'Trop court';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _ibanCtrl,
                        decoration: const InputDecoration(
                            labelText: 'IBAN (optionnel)'),
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _branchCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Agence / Succursale (optionnel)'),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _currency,
                              items: ['MAD', 'EUR', 'USD']
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _currency = v ?? _currency),
                              decoration:
                                  const InputDecoration(labelText: 'Devise'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Compte principal'),
                              value: _isPrimary,
                              onChanged: (v) =>
                                  setState(() => _isPrimary = v ?? false),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _notesCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Notes (optionnel)'),
                        minLines: 2,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _submit,
                              child: _submitting
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Text('Créer'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => context.go('/bank-accounts'),
                              child: const Text('Annuler'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
