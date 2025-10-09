// lib/screens/bank_account_view_screen.dart
// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';

class BankAccountViewScreen extends StatefulWidget {
  final String id;
  const BankAccountViewScreen({Key? key, required this.id}) : super(key: key);

  @override
  State<BankAccountViewScreen> createState() => _BankAccountViewScreenState();
}

class _BankAccountViewScreenState extends State<BankAccountViewScreen> {
  Map<String, dynamic>? _account;
  Map<String, dynamic>? _currentProfile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final acc = await AuthService.getBankAccount(widget.id);
      debugPrint('[BankAccountView] account fetch: $acc');

      Map<String, dynamic>? profile;
      try {
        profile = await AuthService.getProfile();
        debugPrint('[BankAccountView] profile fetched: $profile');
      } catch (e) {
        debugPrint('[BankAccountView] getProfile threw: $e');
        profile = null;
      }

      if (profile == null) {
        try {
          profile = await AuthService.getProfile();
          debugPrint('[BankAccountView] profile fetched on retry: $profile');
        } catch (e) {
          debugPrint('[BankAccountView] getProfile retry threw: $e');
          profile = null;
        }
      }

      if (mounted) {
        _account = acc;
        _currentProfile = profile;
      }
    } catch (e, st) {
      debugPrint('[BankAccountView] load error: $e\n$st');
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat.yMMMd().add_jm().format(dt);
    } catch (_) {
      return iso;
    }
  }

  String _resolveTitulaire(
      Map<String, dynamic>? acc, Map<String, dynamic>? currentProfile) {
    try {
      final ownerName = (acc?['owner_name'] as String?)?.trim();
      if (ownerName != null && ownerName.isNotEmpty) return ownerName;

      final profileFromAcc = acc?['profile'];
      if (profileFromAcc is Map) {
        final nom = (profileFromAcc['nom'] as String?)?.trim();
        final prenom = (profileFromAcc['prenom'] as String?)?.trim();
        if (prenom != null &&
            prenom.isNotEmpty &&
            nom != null &&
            nom.isNotEmpty) {
          return '$prenom $nom';
        }
        if (prenom != null && prenom.isNotEmpty) return prenom;
        if (nom != null && nom.isNotEmpty) return nom;
      }

      if (currentProfile != null) {
        final nom = (currentProfile['nom'] as String?)?.trim();
        final prenom = (currentProfile['prenom'] as String?)?.trim();
        if (prenom != null &&
            prenom.isNotEmpty &&
            nom != null &&
            nom.isNotEmpty) return '$prenom $nom';
        if (prenom != null && prenom.isNotEmpty) return prenom;
        if (nom != null && nom.isNotEmpty) return nom;
      }
    } catch (e) {
      debugPrint('[BankAccountView] resolve titulaire error: $e');
    }
    return '—';
  }

  // Robust IBAN resolution and display (prefer normalized -> raw -> masked)
  String _resolveIbanDisplay(Map<String, dynamic>? acc) {
    try {
      // 1️⃣ IBAN normalisé prioritaire
      final ibanNormalized = (acc?['iban_normalized'] as String?)?.trim();
      if (ibanNormalized != null && ibanNormalized.isNotEmpty) {
        debugPrint('[BankAccountView] using iban_normalized: $ibanNormalized');
        return _formatIban(ibanNormalized);
      }

      // 2️⃣ IBAN brut (non normalisé)
      final ibanRaw = (acc?['iban'] as String?)?.trim();
      if (ibanRaw != null && ibanRaw.isNotEmpty) {
        final clean = ibanRaw.replaceAll(RegExp(r'\s+'), '');
        debugPrint('[BankAccountView] using iban: $clean');
        return _formatIban(clean);
      }

      // 3️⃣ IBAN masqué
      final maskedIban = (acc?['masked_iban'] as String?)?.trim();
      if (maskedIban != null && maskedIban.isNotEmpty) {
        debugPrint('[BankAccountView] using masked_iban: $maskedIban');
        return maskedIban;
      }

      // 4️⃣ Dernier recours : numéro de compte masqué (fallback)
      final maskedAccount = (acc?['masked_account'] as String?)?.trim();
      if (maskedAccount != null && maskedAccount.isNotEmpty) {
        debugPrint(
            '[BankAccountView] fallback to masked_account: $maskedAccount');
        return maskedAccount;
      }
    } catch (e) {
      debugPrint('[BankAccountView] resolve IBAN error: $e');
    }
    return '—';
  }

  String _formatIban(String iban) {
    final clean = iban.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return clean
        .replaceAllMapped(RegExp(r".{1,4}"), (match) => "${match.group(0)} ")
        .trim();
  }

  Widget _buildInfoRow(String label, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Text(value,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ]),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final ButtonStyle elevatedStyle = ElevatedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      minimumSize: const Size(120, 44),
      elevation: 3,
    );

    final ButtonStyle textStyle = TextButton.styleFrom(
      foregroundColor: primaryColor,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      minimumSize: const Size(120, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    final titulaire = _resolveTitulaire(_account, _currentProfile);
    final ibanDisplay = _resolveIbanDisplay(_account);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compte bancaire'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _account == null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        size: 56, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('Compte introuvable',
                        style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                        onPressed: () => context.go('/user-home'),
                        child: const Text('Retour'))
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.blue.shade700,
                                  child: Text(
                                    (_account?['bank_name'] as String? ?? 'B')
                                        .trim()
                                        .split(' ')
                                        .where((s) => s.isNotEmpty)
                                        .map((s) => s[0])
                                        .take(2)
                                        .join()
                                        .toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            _account?['bank_name'] as String? ??
                                                '—',
                                            style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Row(children: [
                                          if ((_account?['is_primary'] == true))
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                  color: Colors.green.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              child: Text('Principal',
                                                  style: TextStyle(
                                                      color:
                                                          Colors.green.shade800,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ),
                                          const SizedBox(width: 8),
                                          Text(
                                              _account?['currency']
                                                      as String? ??
                                                  'EUR',
                                              style: TextStyle(
                                                  color: Colors.grey.shade700)),
                                        ])
                                      ]),
                                )
                              ]),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInfoRow('Titulaire', titulaire),
                                    const Divider(),
                                    _buildInfoRow(
                                      'IBAN',
                                      ibanDisplay,
                                      trailing: IconButton(
                                        tooltip: 'Copier',
                                        icon: const Icon(Icons.copy, size: 20),
                                        onPressed: () {
                                          final toCopy = ibanDisplay;
                                          if (toCopy.isNotEmpty &&
                                              toCopy != '—') {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(const SnackBar(
                                                    content: Text(
                                                        'IBAN copié dans le presse-papiers')));
                                          }
                                        },
                                      ),
                                    ),
                                    const Divider(),
                                    _buildInfoRow(
                                        'Numéro de compte (masqué)',
                                        _account?['masked_account']
                                                as String? ??
                                            '—'),
                                    const Divider(),
                                    _buildInfoRow(
                                        'Banque',
                                        _account?['bank_name'] as String? ??
                                            '—'),
                                    const Divider(),
                                    _buildInfoRow(
                                        'Statut',
                                        (_account?['status'] as String? ?? '—')
                                            .toString()
                                            .toUpperCase()),
                                    const Divider(),
                                    _buildInfoRow(
                                        'Dernière mise à jour',
                                        _formatDate(_account?['updated_at']
                                            ?.toString())),
                                    if ((_account?['verification_metadata'] !=
                                        null))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                            'Vérification: ${_account?['verification_metadata'].toString()}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey)),
                                      ),
                                    if ((_account?['notes'] as String?)
                                            ?.isNotEmpty ==
                                        true) ...[
                                      const SizedBox(height: 8),
                                      const Text('Notes',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey)),
                                      const SizedBox(height: 6),
                                      Text(_account?['notes'] as String? ?? '',
                                          style: const TextStyle(fontSize: 14)),
                                    ]
                                  ]),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.edit, size: 18),
                                      label: const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 8),
                                        child: Text('Modifier',
                                            style: TextStyle(fontSize: 15)),
                                      ),
                                      style: elevatedStyle,
                                      onPressed: () async {
                                        await context.push(
                                            '/bank-account/edit/${widget.id}');
                                        await _load();
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextButton(
                                      style: textStyle,
                                      onPressed: () => context.go('/user-home'),
                                      child: const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 8),
                                        child: Text('Retour au tableau de bord',
                                            style: TextStyle(fontSize: 15)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ]),
                  ),
                ),
    );
  }
}
