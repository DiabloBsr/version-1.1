// lib/screens/history_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../utils/secure_storage.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String _filter =
      'all'; // 'all' | 'transaction' | 'profile_change' | 'bank_account_change'
  String _query = '';
  int _page = 1;
  final int _pageSize = 50;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadAll(reset: true);
  }

  Future<void> _loadAll({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _page = 1;
        _hasMore = true;
        _all = [];
      });
    } else {
      if (!_hasMore || _loadingMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final raw = await SecureStorage.read('local_activities');
      if (raw != null && reset) {
        try {
          final parsedList = jsonDecode(raw) as List<dynamic>;
          final parsed = parsedList.map<Map<String, dynamic>>((e) {
            if (e is Map) return Map<String, dynamic>.from(e);
            if (e is String) {
              return {
                'text': e,
                'timestamp': '',
                'type': 'local',
                'tag': 'local',
                'meta': null,
                'raw': e
              };
            }
            return {
              'text': e.toString(),
              'timestamp': '',
              'type': 'local',
              'tag': 'local',
              'meta': null,
              'raw': e
            };
          }).toList();
          _all.addAll(parsed);
        } catch (e) {
          debugPrint('History local_activities parse error: $e');
        }
      }

      final server =
          await AuthService.getActivities(limit: _pageSize, page: _page);
      if (server.isNotEmpty) {
        final serverParsed = server.map<Map<String, dynamic>>((a) {
          final text = a['text'] ?? a['description'] ?? a.toString();
          final ts =
              a['timestamp']?.toString() ?? a['created_at']?.toString() ?? '';
          final type = a['type']?.toString();
          final tag = a['tag']?.toString();
          final meta = a['meta'];
          return {
            'text': text.toString(),
            'timestamp': ts,
            'type': type,
            'tag': tag,
            'meta': meta,
            'raw': a
          };
        }).toList();
        _all.addAll(serverParsed);
        if (server.length < _pageSize) _hasMore = false;
      } else {
        _hasMore = false;
      }
    } catch (e) {
      debugPrint('History load error: $e');
    } finally {
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    _page += 1;
    try {
      final server =
          await AuthService.getActivities(limit: _pageSize, page: _page);
      if (server.isNotEmpty) {
        final serverParsed = server.map<Map<String, dynamic>>((a) {
          final text = a['text'] ?? a['description'] ?? a.toString();
          final ts =
              a['timestamp']?.toString() ?? a['created_at']?.toString() ?? '';
          final type = a['type']?.toString();
          final tag = a['tag']?.toString();
          final meta = a['meta'];
          return {
            'text': text.toString(),
            'timestamp': ts,
            'type': type,
            'tag': tag,
            'meta': meta,
            'raw': a
          };
        }).toList();
        _all.addAll(serverParsed);
        if (server.length < _pageSize) _hasMore = false;
      } else {
        _hasMore = false;
      }
    } catch (e) {
      debugPrint('History loadMore error: $e');
    } finally {
      setState(() => _loadingMore = false);
    }
  }

  // Format timestamp to "dd/mm/yy à HH:MM:SS"
  String _formatDateTime(String ts) {
    if (ts.isEmpty) return '';
    try {
      final dt = DateTime.parse(ts).toUtc();
      final dd = dt.day.toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final yy = (dt.year % 100).toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      final sec = dt.second.toString().padLeft(2, '0');
      return '$dd/$mm/$yy à $hh:$min:$sec';
    } catch (_) {
      try {
        final clean = ts.replaceAll('Z', '');
        final parts = clean.split('T');
        final datePart = parts.isNotEmpty ? parts[0] : '';
        final timePart = parts.length > 1 ? parts[1].split('.').first : '';
        final dParts = datePart.split('-');
        if (dParts.length >= 3) {
          final dd = dParts[2].padLeft(2, '0');
          final mm = dParts[1].padLeft(2, '0');
          final yy = dParts[0].length == 4 ? dParts[0].substring(2) : dParts[0];
          final time = timePart.isNotEmpty ? timePart.split('+').first : '';
          final normalizedTime = time.isNotEmpty ? time : '00:00:00';
          final timeParts = normalizedTime.split(':');
          final hh = timeParts.length > 0 ? timeParts[0].padLeft(2, '0') : '00';
          final min =
              timeParts.length > 1 ? timeParts[1].padLeft(2, '0') : '00';
          final sec =
              timeParts.length > 2 ? timeParts[2].padLeft(2, '0') : '00';
          return '$dd/$mm/$yy à $hh:$min:$sec';
        }
      } catch (_) {}
      return ts;
    }
  }

  // Profile labels and value maps
  final Map<String, String> _profileLabels = {
    'first_name': 'Prénom',
    'last_name': 'Nom',
    'email': 'Email',
    'phone': 'Téléphone',
    'address': 'Adresse',
    'city': 'Ville',
    'country': 'Pays',
    'avatar': 'Photo de profil',
    'role': 'Rôle',
    'username': 'Nom d’utilisateur',
    'title': 'Titre',
    'position': 'Poste',
    'marital_status': 'Statut marital',
    'status': 'Statut',
    'gender': 'Genre',
    'children_count': 'Nombre d\'enfants',
  };

  final Map<String, Map<String, String>> _profileValueMap = {
    'marital_status': {
      'single': 'Célibataire',
      'married': 'Marié(e)',
      'divorced': 'Divorcé(e)',
      'widowed': 'Veuf(ve)',
      'separated': 'Séparé(e)',
      'unknown': 'Inconnu',
    },
    'gender': {
      'male': 'Homme',
      'female': 'Femme',
      'other': 'Autre',
      'unknown': 'Inconnu',
    },
    'status': {
      'active': 'Actif',
      'inactive': 'Inactif',
      'banned': 'Bloqué',
    },
  };

  // Build readable description for profile diff, e.g. "Statut marital: Marié(e) → Veuf(ve)"
  String _profileDiffToReadable(Map<String, dynamic> diff) {
    final parts = <String>[];
    diff.forEach((k, v) {
      final label = _profileLabels[k] ?? k;
      final oldv = v is Map ? v['old'] : null;
      final newv = v is Map ? v['new'] : null;
      final sensitive = {
        'avatar',
        'password',
        'ssn',
        'iban_encrypted',
        'account_number_encrypted'
      }.contains(k);
      if (sensitive) {
        parts.add(label);
        return;
      }

      String fmtOld = oldv == null ? '' : oldv.toString();
      String fmtNew = newv == null ? '' : newv.toString();

      try {
        final keyLower = k.toLowerCase();
        if (_profileValueMap.containsKey(keyLower)) {
          fmtOld = fmtOld.isNotEmpty
              ? (_profileValueMap[keyLower]?[fmtOld] ?? fmtOld)
              : fmtOld;
          fmtNew = fmtNew.isNotEmpty
              ? (_profileValueMap[keyLower]?[fmtNew] ?? fmtNew)
              : fmtNew;
        } else if (_profileValueMap.containsKey(k)) {
          fmtOld = fmtOld.isNotEmpty
              ? (_profileValueMap[k]?[fmtOld] ?? fmtOld)
              : fmtOld;
          fmtNew = fmtNew.isNotEmpty
              ? (_profileValueMap[k]?[fmtNew] ?? fmtNew)
              : fmtNew;
        }
      } catch (_) {}

      if (fmtOld.isNotEmpty && fmtNew.isNotEmpty) {
        parts.add('$label: $fmtOld → $fmtNew');
      } else if (fmtOld.isEmpty && fmtNew.isNotEmpty) {
        parts.add('$label: $fmtNew');
      } else if (fmtOld.isNotEmpty && fmtNew.isEmpty) {
        parts.add('$label: supprimé');
      }
    });

    if (parts.isEmpty) return 'Informations modifiées';
    final out = parts.join(' • ');
    return out.length > 240 ? out.substring(0, 237) + '...' : out;
  }

  // Build readable description for bank account diffs
  String _bankAccountDiffToReadable(Map<String, dynamic> diff) {
    final labels = {
      'bank_name': 'Banque',
      'bank_code': 'Code banque',
      'agency': 'Agence',
      'currency': 'Devise',
      'iban_encrypted': 'IBAN',
      'account_number_encrypted': 'Numéro de compte',
      'masked_account': 'Compte',
      'is_primary': 'Compte principal',
      'status': 'Statut',
    };
    final parts = <String>[];
    diff.forEach((k, v) {
      final label = labels[k] ?? k;
      final oldv = v is Map ? v['old'] : null;
      final newv = v is Map ? v['new'] : null;
      final sensitive =
          (k == 'iban_encrypted' || k == 'account_number_encrypted');
      if (sensitive) {
        parts.add(label);
      } else {
        if (oldv != null && newv != null) {
          parts.add('$label: ${oldv.toString()} → ${newv.toString()}');
        } else if (oldv == null && newv != null) {
          parts.add('$label: ${newv.toString()}');
        } else if (oldv != null && newv == null) {
          parts.add('$label: supprimé');
        }
      }
    });
    if (parts.isEmpty) return 'Informations du compte modifiées';
    final out = parts.join(' • ');
    return out.length > 240 ? out.substring(0, 237) + '...' : out;
  }

  // Format activity into French title and descriptive subtitle (shows what changed and date/time)
  Map<String, String> _formatActivityFR(Map<String, dynamic> a) {
    final tag = (a['tag'] ?? a['type'] ?? '')?.toString();
    final meta = a['meta'] is Map ? Map<String, dynamic>.from(a['meta']) : null;
    final ts = a['timestamp']?.toString() ?? '';
    final dateTime = _formatDateTime(ts);
    String title = a['text']?.toString() ?? '';
    String subtitle = dateTime;

    if (tag == 'bank_account_change') {
      final action = meta != null ? (meta['action']?.toString() ?? '') : '';
      final diff =
          meta != null ? (meta['diff'] as Map<String, dynamic>?) : null;
      if (action == 'create') {
        title = 'Compte bancaire ajouté';
      } else if (action == 'update') {
        title = 'Compte bancaire modifié';
      } else if (action == 'delete') {
        title = 'Compte bancaire supprimé';
      } else {
        title = 'Changement compte bancaire';
      }
      final readable = diff != null ? _bankAccountDiffToReadable(diff) : '';
      subtitle = readable.isNotEmpty ? '$readable • $dateTime' : dateTime;
    } else if (tag == 'profile_change') {
      final action = meta != null ? (meta['action']?.toString() ?? '') : '';
      final diff =
          meta != null ? (meta['diff'] as Map<String, dynamic>?) : null;
      if (action == 'create') {
        title = 'Profil créé';
      } else if (action == 'update') {
        title = 'Profil modifié';
      } else if (action == 'delete') {
        title = 'Profil supprimé';
      } else {
        title = 'Changement profil';
      }
      final readable = diff != null ? _profileDiffToReadable(diff) : '';
      subtitle = readable.isNotEmpty ? '$readable • $dateTime' : dateTime;
    } else {
      title = a['text']?.toString() ?? '';
      subtitle = dateTime;
    }

    return {'title': title, 'subtitle': subtitle};
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    Iterable<Map<String, dynamic>> items = _all;
    if (_filter == 'transaction') {
      items = items.where((e) =>
          (e['type']?.toString() == 'transaction') ||
          (e['tag']?.toString() == 'transaction') ||
          (e['text']?.toString().toLowerCase().contains('transaction') ??
              false));
    } else if (_filter == 'profile_change') {
      items = items.where((e) =>
          (e['type']?.toString() == 'profile_change') ||
          (e['tag']?.toString() == 'profile_change') ||
          (e['text']?.toString().toLowerCase().contains('profil') ?? false) ||
          (e['text']?.toString().toLowerCase().contains('profil mis') ??
              false));
    } else if (_filter == 'bank_account_change') {
      items = items.where((e) =>
          (e['type']?.toString() == 'bank_account_change') ||
          (e['tag']?.toString() == 'bank_account_change') ||
          (e['text']?.toString().toLowerCase().contains('bank account') ??
              false) ||
          (e['text']?.toString().toLowerCase().contains('compte') ?? false));
    }

    if (q.isNotEmpty) {
      items = items.where((e) =>
          (e['text']?.toString().toLowerCase().contains(q) ?? false) ||
          (e['meta']?.toString().toLowerCase().contains(q) ?? false) ||
          (e['tag']?.toString().toLowerCase().contains(q) ?? false));
    }

    final list = items.toList();
    list.sort((a, b) {
      final ta = a['timestamp']?.toString() ?? '';
      final tb = b['timestamp']?.toString() ?? '';
      if (ta.isEmpty && tb.isEmpty) return 0;
      if (ta.isEmpty) return 1;
      if (tb.isEmpty) return -1;
      return tb.compareTo(ta);
    });
    return list;
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Rechercher dans l\'historique',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.transparent,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrer',
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                  value: 'all',
                  checked: _filter == 'all',
                  child: const Text('Toutes')),
              CheckedPopupMenuItem(
                  value: 'transaction',
                  checked: _filter == 'transaction',
                  child: const Text('Transactions')),
              CheckedPopupMenuItem(
                  value: 'profile_change',
                  checked: _filter == 'profile_change',
                  child: const Text('Modifications profil')),
              CheckedPopupMenuItem(
                  value: 'bank_account_change',
                  checked: _filter == 'bank_account_change',
                  child: const Text('Modifications info compte')),
            ],
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          IconButton(
              onPressed: () => _loadAll(reset: true),
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              _buildFilters(),
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Text('Aucune activité trouvée',
                            style: TextStyle(color: Colors.grey.shade600)))
                    : NotificationListener<ScrollNotification>(
                        onNotification: (ScrollNotification scrollInfo) {
                          if (!_loadingMore &&
                              _hasMore &&
                              scrollInfo.metrics.pixels >=
                                  scrollInfo.metrics.maxScrollExtent - 120) {
                            _loadMore();
                          }
                          return false;
                        },
                        child: ListView.separated(
                          itemCount: _filtered.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            if (i >= _filtered.length) {
                              return Padding(
                                padding: const EdgeInsets.all(12),
                                child: Center(
                                    child: _loadingMore
                                        ? const CircularProgressIndicator()
                                        : const Text('Charger plus')),
                              );
                            }

                            final e = _filtered[i];
                            final formatted = _formatActivityFR(e);
                            final title = formatted['title']!;
                            final subtitle = formatted['subtitle']!;
                            final tag = e['tag']?.toString() ??
                                (e['raw']?['tag']?.toString() ??
                                    (e['type']?.toString() ?? ''));
                            final originalText = e['text']?.toString() ?? '';

                            Widget? trailing;
                            if (tag.isNotEmpty) {
                              trailing = Chip(
                                label: Text(_labelForTagFR(tag),
                                    style: const TextStyle(fontSize: 12)),
                                backgroundColor: tag == 'bank_account_change'
                                    ? Colors.blue.shade50
                                    : tag == 'profile_change'
                                        ? Colors.green.shade50
                                        : Colors.grey.shade100,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 0),
                              );
                            }

                            final leading = CircleAvatar(
                              radius: 18,
                              backgroundColor: tag == 'bank_account_change'
                                  ? Colors.blue.shade100
                                  : tag == 'profile_change'
                                      ? Colors.green.shade100
                                      : Colors.grey.shade200,
                              child: Icon(
                                tag == 'bank_account_change'
                                    ? Icons.account_balance
                                    : tag == 'profile_change'
                                        ? Icons.person
                                        : Icons.info,
                                size: 18,
                                color: Colors.black54,
                              ),
                            );

                            final subtitleWidget = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(subtitle,
                                    style: TextStyle(
                                        color: Colors.black87, fontSize: 13)),
                                if (tag == 'profile_change' &&
                                    originalText.isNotEmpty &&
                                    originalText != title)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      originalText,
                                      style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12),
                                    ),
                                  ),
                              ],
                            );

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              leading: leading,
                              title: Text(title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle:
                                  subtitle.isNotEmpty ? subtitleWidget : null,
                              trailing: trailing,
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Détails activité'),
                                    content: SingleChildScrollView(
                                        child: Text(
                                            const JsonEncoder.withIndent('  ')
                                                .convert(e))),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                          child: const Text('Fermer'))
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
              ),
            ]),
    );
  }

  String _labelForTagFR(String tag) {
    switch (tag) {
      case 'bank_account_change':
        return 'Compte bancaire';
      case 'profile_change':
        return 'Profil';
      case 'transaction':
        return 'Transaction';
      default:
        return tag;
    }
  }
}
