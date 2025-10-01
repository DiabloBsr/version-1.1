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
  String _filter = 'all'; // 'all' | 'transaction' | 'profile_change'
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
      // 1) local stored activities (always include)
      final raw = await SecureStorage.read('local_activities');
      if (raw != null && reset) {
        final parsed = (jsonDecode(raw) as List).map<Map<String, dynamic>>((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          return {'text': e.toString(), 'timestamp': ''};
        }).toList();
        _all.addAll(parsed);
      } else if (raw != null && !reset) {
        // if loading more, do not re-add local entries already present
      }

      // 2) server-side activities (paginated)
      final server =
          await AuthService.getActivities(limit: _pageSize, page: _page);
      if (server.isNotEmpty) {
        final serverParsed = server.map<Map<String, dynamic>>((a) {
          final text = a['text'] ?? a['description'] ?? a.toString();
          final ts = a['timestamp']?.toString() ?? '';
          final type = a['type']?.toString();
          return {
            'text': text.toString(),
            'timestamp': ts,
            'type': type,
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

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    Iterable<Map<String, dynamic>> items = _all;
    if (_filter == 'transaction') {
      items = items.where((e) =>
          (e['type']?.toString() == 'transaction') ||
          (e['text']?.toString().toLowerCase().contains('transaction') ??
              false));
    } else if (_filter == 'profile_change') {
      items = items.where((e) =>
          (e['type']?.toString() == 'profile_change') ||
          (e['text']?.toString().toLowerCase().contains('profil') ?? false) ||
          (e['text']?.toString().toLowerCase().contains('profil mis') ??
              false));
    }
    if (q.isNotEmpty)
      items = items.where((e) =>
          (e['text']?.toString().toLowerCase().contains(q) ?? false) ||
          (e['meta']?.toString().toLowerCase().contains(q) ?? false));
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
          final ts = a['timestamp']?.toString() ?? '';
          final type = a['type']?.toString();
          return {
            'text': text.toString(),
            'timestamp': ts,
            'type': type,
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

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher dans l\'historique'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          icon: const Icon(Icons.filter_list),
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
          ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique complet'),
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
                            final text = e['text']?.toString() ?? '';
                            final ts = e['timestamp']?.toString() ?? '';
                            final type = e['type']?.toString() ??
                                (e['raw']?['type']?.toString() ?? '');
                            return ListTile(
                              title: Text(text),
                              subtitle: ts.isNotEmpty ? Text(ts) : null,
                              trailing: type.isNotEmpty
                                  ? Chip(label: Text(type))
                                  : null,
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Détails activité'),
                                    content: SingleChildScrollView(
                                        child: Text('${jsonEncode(e)}')),
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
}
