// lib/screens/bank_account_edit_screen.dart
// ignore_for_file: unused_field, unused_local_variable

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';

class BankAccountEditScreen extends StatefulWidget {
  final String id;
  const BankAccountEditScreen({Key? key, required this.id}) : super(key: key);

  @override
  State<BankAccountEditScreen> createState() => _BankAccountEditScreenState();
}

class _BankAccountEditScreenState extends State<BankAccountEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _submitting = false;

  late TextEditingController _bankNameCtrl;
  late TextEditingController
      _ownerNameCtrl; // should show username (profile) when owner_name absent
  late TextEditingController
      _accountNumberCtrl; // sensitive; only filled if API exposes plaintext
  late TextEditingController _ibanCtrl;
  late TextEditingController _agencyCtrl; // model field is 'agency'
  late TextEditingController _notesCtrl;
  bool _isPrimary = false;
  String _currency = 'EUR'; // model default

  Map<String, dynamic>? _account;
  Map<String, dynamic>? _currentProfile;
  bool _editable = true; // false when account is deleted/inactive

  @override
  void initState() {
    super.initState();
    _bankNameCtrl = TextEditingController();
    _ownerNameCtrl = TextEditingController();
    _accountNumberCtrl = TextEditingController();
    _ibanCtrl = TextEditingController();
    _agencyCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _ibanCtrl.dispose();
    _agencyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool _determineEditable(Map<String, dynamic> acc) {
    if (acc.isEmpty) return true;
    if (acc.containsKey('deleted') && acc['deleted'] == true) return false;
    if (acc.containsKey('is_active')) return acc['is_active'] == true;
    if (acc.containsKey('active')) return acc['active'] == true;
    final status = (acc['status'] as String?)?.toLowerCase();
    if (status != null)
      return status.contains('active') || status.contains('actif');
    return true;
  }

  String _extractProfileUsername(Map<String, dynamic>? profile) {
    if (profile == null) return '';
    try {
      final username = (profile['username'] as String?)?.trim();
      if (username != null && username.isNotEmpty) return username;
      final user = profile['user'];
      if (user is Map) {
        final userUsername = (user['username'] as String?)?.trim();
        if (userUsername != null && userUsername.isNotEmpty)
          return userUsername;
        final userEmail = (user['email'] as String?)?.trim();
        if (userEmail != null && userEmail.isNotEmpty) return userEmail;
      }
      final fullName = (profile['full_name'] as String?)?.trim() ??
          (profile['name'] as String?)?.trim();
      if (fullName != null && fullName.isNotEmpty) return fullName;
      final id = profile['id']?.toString();
      if (id != null) return id;
    } catch (_) {}
    return '';
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final acc = await AuthService.getBankAccount(widget.id);
      Map<String, dynamic>? profile;
      try {
        profile = await AuthService.getProfile();
      } catch (_) {
        profile = null;
      }

      if (mounted) {
        _account = acc;
        _currentProfile = profile;

        _bankNameCtrl.text = (acc?['bank_name'] as String?) ?? '';

        final ownerName = (acc?['owner_name'] as String?)?.trim();
        if (ownerName != null && ownerName.isNotEmpty) {
          _ownerNameCtrl.text = ownerName;
        } else {
          _ownerNameCtrl.text = _extractProfileUsername(profile);
        }

        _accountNumberCtrl.text = (acc?['account_number'] as String?) ?? '';
        _ibanCtrl.text = (acc?['iban'] as String?) ??
            (acc?['iban_normalized'] as String?) ??
            '';
        _agencyCtrl.text = (acc?['agency'] as String?) ??
            (acc?['branch_name'] as String?) ??
            '';
        _notesCtrl.text = (acc?['notes'] as String?) ?? '';
        _isPrimary = acc?['is_primary'] == true;
        _currency = (acc?['currency'] as String?) ?? _currency;
        _editable = acc != null ? _determineEditable(acc) : true;
      }
    } catch (e, st) {
      debugPrint('[BankAccountEdit] load error: $e\n$st');
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur chargement: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_editable) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Compte non modifiable')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;
    setState(() => _submitting = true);

    try {
      final existing = await AuthService.getBankAccount(widget.id);
      if (existing == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Compte introuvable')));
          context.go('/bank-accounts');
        }
        return;
      }

      final payload = <String, dynamic>{};

      void addIfChanged(String key, String? newValue) {
        final old = (existing[key] as String?) ?? '';
        if ((newValue ?? '').trim() != old.trim())
          payload[key] = newValue?.trim();
      }

      addIfChanged('bank_name', _bankNameCtrl.text);
      addIfChanged('owner_name', _ownerNameCtrl.text);
      addIfChanged('account_number', _accountNumberCtrl.text);
      addIfChanged('iban', _ibanCtrl.text);
      addIfChanged('agency', _agencyCtrl.text);
      addIfChanged('notes', _notesCtrl.text);

      if ((_isPrimary != (existing['is_primary'] == true)))
        payload['is_primary'] = _isPrimary;
      if ((_currency != (existing['currency'] as String? ?? '')))
        payload['currency'] = _currency;

      if (payload.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Aucune modification détectée')));
        return;
      }

      final base = AuthService.apiBase;
      final candidates = [
        Uri.parse('$base/bank-accounts/${widget.id}/'),
        Uri.parse('$base/bank-accounts/${widget.id}'),
      ];

      Future<http.Response> doPatch(Uri uri, String token) => http
          .patch(uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
                'Accept': 'application/json'
              },
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));

      Future<http.Response> doPut(Uri uri, String token) => http
          .put(uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
                'Accept': 'application/json'
              },
              body: jsonEncode({...existing, ...payload}))
          .timeout(const Duration(seconds: 20));

      http.Response resp;
      Uri used = candidates.first;

      resp = await AuthService.authenticatedRequest(
          (token) async => doPatch(used, token));

      if (resp.statusCode == 404) {
        final other =
            candidates.firstWhere((u) => u != used, orElse: () => used);
        if (other != used) {
          used = other;
          resp = await AuthService.authenticatedRequest(
              (token) async => doPatch(used, token));
        }
      }

      if (resp.statusCode == 405 || resp.statusCode == 400) {
        resp = await AuthService.authenticatedRequest(
            (token) async => doPut(used, token));
      }

      debugPrint(
          '[BankAccountEdit] update ${used.toString()} => ${resp.statusCode} ${resp.body}');

      if (resp.statusCode == 200 || resp.statusCode == 204) {
        final fresh = await AuthService.getBankAccount(widget.id);
        bool persisted = false;
        if (fresh != null) {
          persisted = true;
          for (final k in payload.keys) {
            final newVal = payload[k];
            final remoteVal = fresh[k];

            if (newVal is bool) {
              if (remoteVal == newVal) continue;
              persisted = false;
              break;
            } else {
              final sNew = (newVal ?? '').toString().trim();
              final sRem = (remoteVal ?? '').toString().trim();
              if (sNew == sRem) continue;

              if (k == 'iban') {
                final normalizedSent =
                    sNew.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
                final serverNormalized =
                    (fresh['iban_normalized'] as String?) ?? '';
                if (normalizedSent == serverNormalized) continue;
              }

              persisted = false;
              break;
            }
          }
        }

        if (persisted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Compte mis à jour')));
          await _load();
          context.go('/bank-accounts');
          return;
        } else {
          String serverMsg =
              'Réponse ${resp.statusCode} mais les modifications ne semblent pas appliquées';
          try {
            final parsed = jsonDecode(resp.body);
            serverMsg = parsed is Map ? parsed.toString() : parsed.toString();
          } catch (_) {}
          if (mounted)
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Erreur: $serverMsg')));
          await _load();
          return;
        }
      }

      String err = 'HTTP ${resp.statusCode}';
      try {
        final parsed = jsonDecode(resp.body);
        if (parsed is Map) {
          final parts = <String>[];
          parsed.forEach((k, v) {
            parts.add('$k: ${v is List ? v.join(', ') : v}');
          });
          err = parts.join(' | ');
        } else {
          err = parsed.toString();
        }
      } catch (_) {
        if (resp.body.isNotEmpty) err = resp.body;
      }

      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur serveur: $err')));
    } catch (e, st) {
      debugPrint('[BankAccountEdit] submit error: $e\n$st');
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final dangerColor = Colors.red;

    final ButtonStyle elevatedStyle = ElevatedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      minimumSize: const Size(120, 44),
      elevation: 2,
    );

    final ButtonStyle outlinedStyle = OutlinedButton.styleFrom(
      side: BorderSide(color: dangerColor.withOpacity(0.12)),
      backgroundColor: Colors.red.withOpacity(0.02),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      minimumSize: const Size(120, 44),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier le compte'),
        actions: [
          IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
              onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _bankNameCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Nom de la banque'),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Requis'
                                  : null,
                              enabled: _editable,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _ownerNameCtrl,
                              decoration: InputDecoration(
                                labelText: 'Titulaire (nom d\'utilisateur)',
                                helperText: (_account != null &&
                                        (_account?['owner_name'] as String?)
                                                ?.isNotEmpty !=
                                            true)
                                    ? 'Nom d\'utilisateur courant: ${_extractProfileUsername(_currentProfile)}'
                                    : null,
                              ),
                              enabled: _editable,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _accountNumberCtrl,
                              decoration: InputDecoration(
                                labelText:
                                    'Numéro de compte (laisser vide pour ne pas modifier)',
                                helperText:
                                    _account?['masked_account'] as String? ??
                                        '',
                              ),
                              keyboardType: TextInputType.text,
                              enabled: _editable,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                                controller: _ibanCtrl,
                                decoration:
                                    const InputDecoration(labelText: 'IBAN'),
                                enabled: _editable),
                            const SizedBox(height: 12),
                            TextFormField(
                                controller: _agencyCtrl,
                                decoration:
                                    const InputDecoration(labelText: 'Agence'),
                                enabled: _editable),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _currency,
                                    items: ['EUR', 'MAD', 'USD']
                                        .map((c) => DropdownMenuItem(
                                            value: c, child: Text(c)))
                                        .toList(),
                                    onChanged: _editable
                                        ? (v) => setState(
                                            () => _currency = v ?? _currency)
                                        : null,
                                    decoration: const InputDecoration(
                                        labelText: 'Devise'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Compte principal'),
                                    value: _isPrimary,
                                    onChanged: _editable
                                        ? (v) => setState(
                                            () => _isPrimary = v ?? false)
                                        : null,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
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
                                enabled: _editable),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 140,
                                  child: ElevatedButton.icon(
                                    onPressed: (_submitting || !_editable)
                                        ? null
                                        : _submit,
                                    icon: _submitting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white))
                                        : const Icon(Icons.save, size: 18),
                                    label: const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 6),
                                        child: Text('Enregistrer',
                                            style: TextStyle(fontSize: 14))),
                                    style: elevatedStyle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 140,
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        context.go('/bank-accounts'),
                                    style: outlinedStyle,
                                    child: const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 6),
                                        child: Text('Annuler',
                                            style: TextStyle(fontSize: 14))),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!_editable)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                          'Ce compte est supprimé ou inactif et ne peut pas être modifié.',
                          style: TextStyle(color: Colors.grey.shade700)),
                    ),
                ],
              ),
            ),
    );
  }
}
