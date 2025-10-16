// lib/screens/bank_account_view_screen.dart
// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../auth_state.dart';

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

  // account reveal state
  bool _accountRevealed = false;
  bool _revealingInProgress = false;

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
        _accountRevealed = false;
      }
    } catch (e, st) {
      debugPrint('[BankAccountView] load error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
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

  // IBAN resolution: prefer normalized -> raw -> masked_iban. Do NOT fallback to masked_account.
  String _resolveIbanDisplay(Map<String, dynamic>? acc) {
    try {
      final ibanNormalized = (acc?['iban_normalized'] as String?)?.trim();
      if (ibanNormalized != null && ibanNormalized.isNotEmpty) {
        debugPrint('[BankAccountView] using iban_normalized: $ibanNormalized');
        return _formatIban(ibanNormalized);
      }

      final ibanRaw = (acc?['iban'] as String?)?.trim();
      if (ibanRaw != null && ibanRaw.isNotEmpty) {
        final clean = ibanRaw.replaceAll(RegExp(r'\s+'), '');
        debugPrint('[BankAccountView] using iban: $clean');
        return _formatIban(clean);
      }

      final maskedIban = (acc?['masked_iban'] as String?)?.trim();
      if (maskedIban != null && maskedIban.isNotEmpty) {
        debugPrint('[BankAccountView] using masked_iban: $maskedIban');
        return maskedIban;
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

  Widget _buildInfoRow(String label, Widget valueWidget, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            valueWidget,
          ]),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }

  // Left quick menu adapted to match user_home_screen's left menu style (MenuButton)
  Widget _leftQuickMenu(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 10, offset: Offset(0, 6))
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Actions rapides',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).textTheme.bodyMedium?.color)),
          const SizedBox(height: 12),

          // Accueil button ajouté en haut
          _MenuButton(
            icon: Icons.home,
            label: 'Accueil',
            onTap: () => context.go('/user-home'),
          ),
          const SizedBox(height: 8),

          _MenuButton(
            icon: Icons.person,
            label: 'Profil',
            onTap: () => context.go('/profile'),
          ),
          const SizedBox(height: 8),
          _MenuButton(
            icon: Icons.account_balance,
            label: 'Comptes bancaires',
            color: Colors.blue,
            // mark active visually by disabling onTap
            onTap: null,
            active: true,
          ),
          const SizedBox(height: 8),
          _MenuButton(
            icon: Icons.history,
            label: 'Historique',
            onTap: () => context.go('/history'),
          ),
          const SizedBox(height: 8),
          _MenuButton(
            icon: Icons.logout,
            label: 'Se déconnecter',
            color: Colors.orange,
            onTap: () async {
              debugPrint('[BankAccountView] logout tapped');

              final confirm = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) {
                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            'DECONNEXION',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.logout,
                              color: Colors.orange.shade700, size: 24),
                        ),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'Vous allez être déconnecté. Voulez-vous continuer ?',
                          style: TextStyle(height: 1.4, fontSize: 20),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 12),
                      ],
                    ),
                    actionsAlignment: MainAxisAlignment.center,
                    actions: [
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.onSurface,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Text('Annuler'),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text('Se déconnecter',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                        ),
                      ),
                    ],
                  );
                },
              );

              debugPrint('[BankAccountView] logout confirm result: $confirm');
              if (confirm != true) return;

              try {
                debugPrint('[BankAccountView] proceeding with logout');
                await AuthService.logoutAndClear();
              } catch (e) {
                debugPrint('[BankAccountView] logout error: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Erreur lors de la déconnexion')),
                  );
                }
              } finally {
                try {
                  final authState =
                      Provider.of<AuthState>(context, listen: false);
                  authState.markLoggedOutSync();
                } catch (_) {}
                if (!mounted) return;
                context.go('/login');
              }
            },
          ),
        ]),
      ),
    );
  }

  Widget _MenuButton(
      {required IconData icon,
      required String label,
      VoidCallback? onTap,
      Color? color,
      bool active = false}) {
    return _MenuButtonWidget(
      icon: icon,
      label: label,
      onTap: onTap,
      color: color,
      active: active,
    );
  }

  Widget _fixedFooter(BuildContext context) {
    final version = AuthService.appVersion ?? 'unknown';
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: Row(children: [
        Text('Version: $version',
            style: TextStyle(color: Colors.grey.shade700)),
        const Spacer(),
        const SizedBox(width: 8),
      ]),
    );
  }

  // helper: account number retrieval (full) with multiple possible keys
  String? _resolveFullAccountNumber(Map<String, dynamic>? acc) {
    final candidates = <String?>[
      (acc?['account_number'] as String?),
      (acc?['raw_account'] as String?),
      (acc?['number'] as String?),
      (acc?['acct_number'] as String?),
    ];
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }

  // agency resolution: try several keys
  String _resolveAgency(Map<String, dynamic>? acc) {
    final keys = ['agency_name', 'agency', 'branch_name', 'branch'];
    for (final k in keys) {
      final v = (acc?[k] as String?)?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    // sometimes agency is an object
    final agencyObj = acc?['agency'];
    if (agencyObj is Map) {
      final name = (agencyObj['name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return '—';
  }

  // Verify password with a retry after token refresh if needed.
  // This addresses cases where verifyPassword fails due to expired token.
  Future<bool> _promptForPasswordAndVerify() async {
    if (!mounted) return false;
    String password = '';
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirmer pour afficher'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Veuillez saisir votre mot de passe pour afficher le numéro de compte.'),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              obscureText: true,
              onChanged: (v) => password = v,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), labelText: 'Mot de passe'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuler')),
            ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Valider')),
          ],
        );
      },
    );

    if (ok != true) return false;
    setState(() => _revealingInProgress = true);
    try {
      final pwd = password.trim();
      debugPrint(
          '[BankAccountView] verify: starting verification attempt; password_length=${pwd.length}');
      if (pwd.isEmpty) {
        debugPrint(
            '[BankAccountView] verify: aborted because password is empty');
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Mot de passe vide')));
        }
        return false;
      }

      // First attempt
      bool verified = false;
      try {
        debugPrint(
            '[BankAccountView] verify: calling AuthService.verifyPassword (attempt 1)');
        verified = await AuthService.verifyPassword(pwd);
        debugPrint(
            '[BankAccountView] verify: AuthService.verifyPassword returned: $verified');
      } catch (e, st) {
        debugPrint(
            '[BankAccountView] verify: AuthService.verifyPassword threw: $e\n$st');
        verified = false;
      }

      // If verifyPassword returns false, attempt a token refresh then retry once.
      if (!verified) {
        try {
          debugPrint(
              '[BankAccountView] verify: first attempt failed — calling AuthService.refreshTokens()');
          final refreshed = await AuthService.refreshTokens();
          debugPrint(
              '[BankAccountView] verify: refreshTokens returned: $refreshed');
          if (refreshed) {
            try {
              debugPrint(
                  '[BankAccountView] verify: retrying AuthService.verifyPassword (attempt 2) after refresh');
              verified = await AuthService.verifyPassword(pwd);
              debugPrint(
                  '[BankAccountView] verify: AuthService.verifyPassword (attempt 2) returned: $verified');
            } catch (e, st) {
              debugPrint(
                  '[BankAccountView] verify: verifyPassword retry threw: $e\n$st');
              verified = false;
            }
          } else {
            debugPrint(
                '[BankAccountView] verify: refreshTokens returned false; not retrying verifyPassword');
          }
        } catch (e, st) {
          debugPrint('[BankAccountView] verify: refreshTokens threw: $e\n$st');
        }
      }

      if (!verified) {
        debugPrint('[BankAccountView] verify: final result -> NOT verified');
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Mot de passe incorrect')));
        return false;
      }

      debugPrint('[BankAccountView] verify: final result -> verified');
      return true;
    } catch (e, st) {
      debugPrint('[BankAccountView] password verify unexpected error: $e\n$st');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur lors de la vérification')));
      return false;
    } finally {
      if (mounted) setState(() => _revealingInProgress = false);
    }
  }

  // Helper to render masked account: show only last 4 digits with bullets
  String _maskedAccountFor(String full) {
    final clean = full.replaceAll(RegExp(r'\s+'), '');
    if (clean.length <= 4) return '••••';
    final last = clean.substring(clean.length - 4);
    return '${'•' * (clean.length - 4)}$last';
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
    final fullAccount = _resolveFullAccountNumber(_account);
    final maskedAccountDisplay = fullAccount != null
        ? _maskedAccountFor(fullAccount)
        : (_account?['masked_account'] as String?)?.trim() ?? '—';
    final agencyName = _resolveAgency(_account);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compte bancaire'),
        actions: [
          IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
              onPressed: _load)
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left menu (hidden on narrow screens)
                LayoutBuilder(builder: (context, constraints) {
                  if (constraints.maxWidth < 1000)
                    return const SizedBox.shrink();
                  return Padding(
                      padding:
                          const EdgeInsets.only(left: 18, top: 18, bottom: 18),
                      child: _leftQuickMenu(context));
                }),
                // Main content
                Expanded(
                  child: _account == null
                      ? Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.account_balance_wallet_outlined,
                              size: 56, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text('Compte introuvable',
                              style: TextStyle(fontSize: 16)),
                          const SizedBox(height: 8),
                          ElevatedButton(
                              onPressed: () => context.go('/user-home'),
                              child: const Text('Retour'))
                        ]))
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
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(children: [
                                        CircleAvatar(
                                          radius: 30,
                                          backgroundColor: Colors.blue.shade700,
                                          child: Text(
                                            (_account?['bank_name']
                                                        as String? ??
                                                    'B')
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
                                                    _account?['bank_name']
                                                            as String? ??
                                                        '—',
                                                    style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                const SizedBox(height: 6),
                                                Row(children: [
                                                  if ((_account?[
                                                          'is_primary'] ==
                                                      true))
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4),
                                                      decoration: BoxDecoration(
                                                          color: Colors
                                                              .green.shade50,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12)),
                                                      child: Text('Principal',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .green
                                                                  .shade800,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600)),
                                                    ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                      _account?['currency']
                                                              as String? ??
                                                          'EUR',
                                                      style: TextStyle(
                                                          color: Colors
                                                              .grey.shade700)),
                                                ])
                                              ]),
                                        )
                                      ]),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Card(
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    elevation: 1,
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildInfoRow(
                                                'Titulaire',
                                                Text(titulaire,
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600))),
                                            const Divider(),
                                            // IBAN row: use ibanDisplay which no longer falls back to masked_account
                                            _buildInfoRow(
                                              'IBAN',
                                              Text(ibanDisplay,
                                                  style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                              trailing: IconButton(
                                                tooltip: 'Copier',
                                                icon: const Icon(Icons.copy,
                                                    size: 20),
                                                onPressed: () {
                                                  final toCopy = ibanDisplay;
                                                  if (toCopy.isNotEmpty &&
                                                      toCopy != '—') {
                                                    Clipboard.setData(
                                                        ClipboardData(
                                                            text: toCopy));
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                            const SnackBar(
                                                                content: Text(
                                                                    'IBAN copié dans le presse-papiers')));
                                                  }
                                                },
                                              ),
                                            ),
                                            const Divider(),
                                            // Numéro de compte: inline display and copy when revealed (no duplicated footer)
                                            _buildInfoRow(
                                              'Numéro de compte',
                                              Row(children: [
                                                Expanded(
                                                  child: Text(
                                                    (_accountRevealed &&
                                                            fullAccount != null)
                                                        ? fullAccount
                                                        : maskedAccountDisplay,
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600),
                                                  ),
                                                ),
                                              ]),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (_revealingInProgress)
                                                    const SizedBox(
                                                        width: 36,
                                                        height: 36,
                                                        child:
                                                            CircularProgressIndicator(
                                                                strokeWidth: 2))
                                                  else ...[
                                                    if (_accountRevealed &&
                                                        fullAccount != null)
                                                      IconButton(
                                                        tooltip:
                                                            'Copier le numéro de compte',
                                                        icon: const Icon(
                                                            Icons.copy,
                                                            size: 20),
                                                        onPressed: () async {
                                                          try {
                                                            await Clipboard.setData(
                                                                ClipboardData(
                                                                    text:
                                                                        fullAccount));
                                                            if (mounted) {
                                                              ScaffoldMessenger
                                                                      .of(
                                                                          context)
                                                                  .showSnackBar(
                                                                      const SnackBar(
                                                                          content:
                                                                              Text('Numéro de compte copié dans le presse-papiers')));
                                                            }
                                                          } catch (e) {
                                                            debugPrint(
                                                                '[BankAccountView] copy account error: $e');
                                                            if (mounted) {
                                                              ScaffoldMessenger
                                                                      .of(
                                                                          context)
                                                                  .showSnackBar(
                                                                      const SnackBar(
                                                                          content:
                                                                              Text('Erreur lors de la copie')));
                                                            }
                                                          }
                                                        },
                                                      ),
                                                    IconButton(
                                                      tooltip: _accountRevealed
                                                          ? 'Masquer'
                                                          : 'Afficher',
                                                      icon: Icon(
                                                          _accountRevealed
                                                              ? Icons
                                                                  .visibility_off
                                                              : Icons
                                                                  .visibility,
                                                          size: 20),
                                                      onPressed: () async {
                                                        if (_accountRevealed) {
                                                          setState(() =>
                                                              _accountRevealed =
                                                                  false);
                                                          return;
                                                        }
                                                        final full =
                                                            fullAccount;
                                                        if (full == null) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                                  const SnackBar(
                                                                      content: Text(
                                                                          'Numéro complet non disponible')));
                                                          return;
                                                        }

                                                        final ok =
                                                            await _promptForPasswordAndVerify();
                                                        if (!ok) return;
                                                        setState(() =>
                                                            _accountRevealed =
                                                                true);
                                                      },
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const Divider(),
                                            _buildInfoRow(
                                                'Banque',
                                                Text(
                                                    _account?['bank_name']
                                                            as String? ??
                                                        '—',
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600))),
                                            const Divider(),
                                            _buildInfoRow(
                                                'Agence',
                                                Text(agencyName,
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600))),
                                            const Divider(),
                                            _buildInfoRow(
                                                'Statut',
                                                Text(
                                                    (_account?['status']
                                                                as String? ??
                                                            '—')
                                                        .toString()
                                                        .toUpperCase(),
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600))),
                                            const Divider(),
                                            _buildInfoRow(
                                                'Dernière mise à jour',
                                                Text(
                                                    _formatDate(
                                                        _account?['updated_at']
                                                            ?.toString()),
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600))),
                                            if ((_account?[
                                                    'verification_metadata'] !=
                                                null))
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8),
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
                                              Text(
                                                  _account?['notes']
                                                          as String? ??
                                                      '',
                                                  style: const TextStyle(
                                                      fontSize: 14)),
                                            ]
                                          ]),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Center(
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 520),
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                icon: const Icon(Icons.edit,
                                                    size: 18),
                                                label: const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      vertical: 8),
                                                  child: Text('Modifier',
                                                      style: TextStyle(
                                                          fontSize: 15)),
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
                                                onPressed: () =>
                                                    context.go('/user-home'),
                                                child: const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      vertical: 8),
                                                  child: Text(
                                                      'Retour au tableau de bord',
                                                      style: TextStyle(
                                                          fontSize: 15)),
                                                ),
                                              ),
                                            ),
                                          ]),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ]),
                          ),
                        ),
                ),
              ],
            ),
      // Floating assistant icon and fixed footer same as user_home
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/support'),
        tooltip: 'Aide / Support',
        child: const Icon(Icons.support_agent_outlined),
      ),
      bottomNavigationBar: _fixedFooter(context),
    );
  }
}

/// Menu button styled like user_home_screen's menu
class _MenuButtonWidget extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool active;

  const _MenuButtonWidget({
    Key? key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.active = false,
  }) : super(key: key);

  @override
  State<_MenuButtonWidget> createState() => _MenuButtonWidgetState();
}

class _MenuButtonWidgetState extends State<_MenuButtonWidget> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovering
        ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
        : Colors.transparent;
    final iconBg = _hovering ? Theme.of(context).colorScheme.primary : null;
    final textColor = _hovering ? Theme.of(context).colorScheme.primary : null;

    final effectiveIconBg = widget.active
        ? Theme.of(context).colorScheme.primary
        : (iconBg ?? widget.color ?? Colors.blue.shade700);
    final effectiveTextColor = widget.active
        ? Theme.of(context).colorScheme.primary
        : (textColor ?? Theme.of(context).textTheme.bodyMedium?.color);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor:
          widget.active ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.active ? null : widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: effectiveIconBg,
                  child: Icon(widget.icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: effectiveTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_hovering && !widget.active)
                  Icon(Icons.arrow_forward_ios,
                      size: 14, color: effectiveTextColor),
                if (widget.active)
                  Icon(Icons.check,
                      size: 14, color: Theme.of(context).colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
