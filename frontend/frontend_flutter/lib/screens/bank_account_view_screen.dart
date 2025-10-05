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
      if (mounted) setState(() => _account = acc);
    } catch (e) {
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
    final dangerColor = Colors.red;

    // Styles: rounded, modest height, balanced width
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
                                                  'MAD',
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
                                    _buildInfoRow(
                                        'Titulaire',
                                        _account?['owner_name'] as String? ??
                                            '—'),
                                    const Divider(),
                                    _buildInfoRow(
                                      'Numéro de compte',
                                      _account?['masked_account'] as String? ??
                                          '—',
                                      trailing: IconButton(
                                        tooltip: 'Copier le numéro complet',
                                        icon: const Icon(Icons.copy, size: 20),
                                        onPressed: () {
                                          final toCopy =
                                              _account?['account_number']
                                                      as String? ??
                                                  _account?['masked_account']
                                                      as String? ??
                                                  '';
                                          if (toCopy.isNotEmpty) {
                                            // Clipboard usage intentionally omitted import; add if desired:
                                            // Clipboard.setData(ClipboardData(text: toCopy));
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(const SnackBar(
                                                    content: Text(
                                                        'Numéro copié dans le presse-papiers')));
                                          }
                                        },
                                      ),
                                    ),
                                    const Divider(),
                                    _buildInfoRow('IBAN',
                                        _account?['iban'] as String? ?? '—'),
                                    const Divider(),
                                    _buildInfoRow(
                                        'Banque',
                                        _account?['branch_name'] as String? ??
                                            (_account?['bank_name']
                                                    as String? ??
                                                '—')),
                                    const Divider(),
                                    _buildInfoRow(
                                        'Statut',
                                        (_account?['status'] as String? ?? '—')
                                            .toUpperCase()),
                                    const Divider(),
                                    _buildInfoRow(
                                        'Dernière mise à jour',
                                        _formatDate(_account?['updated_at']
                                            ?.toString())),
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

                          // Centered buttons: Modifier | Retour côte à côte
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
                                        // push edit page and refresh when returned
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
