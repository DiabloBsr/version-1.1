// lib/screens/profile_edit_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../utils/secure_storage.dart';
import '../services/auth_service.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({Key? key}) : super(key: key);

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _originalProfile; // snapshot taken on open

  // form controllers
  final TextEditingController _nomCtrl = TextEditingController();
  final TextEditingController _prenomCtrl = TextEditingController();
  final TextEditingController _telephoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _adresseCtrl = TextEditingController();
  final TextEditingController _cinNumeroCtrl = TextEditingController();
  final TextEditingController _cinDateCtrl = TextEditingController();
  final TextEditingController _lieuNaissCtrl = TextEditingController();
  int _nombreEnfants = 0;
  String? _sexe; // "M" or "F"
  String? _situation; // marital choice
  DateTime? _dateNaissance;

  // image picks: use XFile for cross-platform
  XFile? _pickedXFile;
  Uint8List? _pickedBytes; // preview for web

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    _telephoneCtrl.dispose();
    _emailCtrl.dispose();
    _adresseCtrl.dispose();
    _cinNumeroCtrl.dispose();
    _cinDateCtrl.dispose();
    _lieuNaissCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final pServer = await AuthService.getProfile();
      if (pServer == null) {
        if (mounted) context.go('/login');
        return;
      }
      _profile = pServer;
      // store original snapshot for diffing after save
      _originalProfile = Map<String, dynamic>.from(pServer);

      _nomCtrl.text = (pServer['nom'] ?? '') as String;
      _prenomCtrl.text = (pServer['prenom'] ?? '') as String;
      _telephoneCtrl.text = (pServer['telephone'] ?? '') as String;
      _emailCtrl.text =
          ((pServer['email'] ?? pServer['user']?['email']) ?? '') as String;
      _adresseCtrl.text = (pServer['adresse'] ?? '') as String;
      _cinNumeroCtrl.text = (pServer['cin_numero'] ?? '') as String;
      _cinDateCtrl.text = (pServer['cin_date_delivrance'] ?? '') as String;
      _lieuNaissCtrl.text = (pServer['lieu_naissance'] ?? '') as String;
      _nombreEnfants = (pServer['nombre_enfants'] is int)
          ? pServer['nombre_enfants'] as int
          : int.tryParse('${pServer['nombre_enfants'] ?? 0}') ?? 0;
      _sexe = (pServer['sexe'] as String?)?.isNotEmpty == true
          ? pServer['sexe'] as String
          : null;
      _situation =
          (pServer['situation_matrimoniale'] as String?)?.isNotEmpty == true
              ? pServer['situation_matrimoniale'] as String
              : null;
      if (pServer['date_naissance'] != null) {
        try {
          _dateNaissance = DateTime.parse(pServer['date_naissance']);
        } catch (_) {
          _dateNaissance = null;
        }
      }
    } catch (e, st) {
      debugPrint('ProfileEdit _loadProfile error: $e\n$st');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible de charger le profil')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage(ImageSource src) async {
    try {
      final XFile? x = await _picker.pickImage(
          source: src, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (x == null) return;
      _pickedXFile = x;
      if (kIsWeb) {
        _pickedBytes = await x.readAsBytes();
      } else {
        _pickedBytes = null;
      }
      setState(() {});
    } catch (e, st) {
      debugPrint('pickImage error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur sélection image')));
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _dateNaissance ?? DateTime(now.year - 25);
    final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(1900),
        lastDate: now);
    if (picked != null) setState(() => _dateNaissance = picked);
  }

  bool _validateEmail(String v) {
    final re = RegExp(r"^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$");
    return re.hasMatch(v);
  }

  Future<void> _storeLocalActivities(List<Map<String, dynamic>> entries) async {
    try {
      final raw = await SecureStorage.read('local_activities');
      List existing = raw != null ? jsonDecode(raw) as List : [];
      existing = [...entries, ...existing];
      await SecureStorage.write('local_activities', jsonEncode(existing));
      debugPrint('[ProfileEdit] stored local activities: ${entries.length}');
    } catch (e) {
      debugPrint('[ProfileEdit] failed to store local activities: $e');
    }
  }

  List<String> _computeProfileDiffLocal(
      Map<String, dynamic>? prev, Map<String, dynamic>? next) {
    if (prev == null || next == null) return [];
    final List<String> changes = [];

    String _valueToString(dynamic v) {
      if (v == null) return '';
      if (v is int) return v.toString();
      return v.toString();
    }

    void checkField(String key, String label, {bool allowEmpty = true}) {
      final a = _valueToString(prev[key]);
      final b = _valueToString(next[key]);
      if (a != b) {
        if (!allowEmpty && a.isEmpty && b.isEmpty) return;
        changes.add('$label: "$a" → "$b"');
      }
    }

    checkField('prenom', 'Prénom');
    checkField('nom', 'Nom');
    checkField('email', 'Email');
    checkField('telephone', 'Téléphone');
    checkField('adresse', 'Adresse');
    checkField('lieu_naissance', 'Lieu de naissance');
    checkField('cin_numero', 'Numéro CIN');
    checkField('cin_date_delivrance', 'Date délivrance CIN');
    checkField('nombre_enfants', 'Nombre d\'enfants');
    checkField('sexe', 'Sexe');
    checkField('situation_matrimoniale', 'Situation');

    final prevDate = prev['date_naissance']?.toString() ?? '';
    final nextDate = next['date_naissance']?.toString() ?? '';
    if (prevDate != nextDate)
      changes.add('Date de naissance: "$prevDate" → "$nextDate"');

    final prevPhoto = (prev['photo'] as String?) ??
        (prev['user'] is Map ? prev['user']['photo'] as String? : null);
    final nextPhoto = (next['photo'] as String?) ??
        (next['user'] is Map ? next['user']['photo'] as String? : null);
    if (prevPhoto != nextPhoto) {
      if ((prevPhoto ?? '').isEmpty && (nextPhoto ?? '').isNotEmpty)
        changes.add('Photo de profil: ajoutée');
      else if ((prevPhoto ?? '').isNotEmpty && (nextPhoto ?? '').isEmpty)
        changes.add('Photo de profil: supprimée');
      else
        changes.add('Photo de profil: mise à jour');
    }

    return changes;
  }

  Future<bool> _submit() async {
    if (!_formKey.currentState!.validate()) return false;
    if (!mounted) return false;
    setState(() => _saving = true);

    try {
      final extra = <String, String>{};
      if (_adresseCtrl.text.trim().isNotEmpty)
        extra['adresse'] = _adresseCtrl.text.trim();
      if (_cinNumeroCtrl.text.trim().isNotEmpty)
        extra['cin_numero'] = _cinNumeroCtrl.text.trim();
      if (_cinDateCtrl.text.trim().isNotEmpty)
        extra['cin_date_delivrance'] = _cinDateCtrl.text.trim();
      if (_lieuNaissCtrl.text.trim().isNotEmpty)
        extra['lieu_naissance'] = _lieuNaissCtrl.text.trim();
      extra['nombre_enfants'] = '$_nombreEnfants';
      if (_sexe != null) extra['sexe'] = _sexe!;
      if (_situation != null) extra['situation_matrimoniale'] = _situation!;
      if (_dateNaissance != null)
        extra['date_naissance'] =
            _dateNaissance!.toIso8601String().split('T').first;

      // NOTE: do NOT allow role change here (reserved to admin) - do not include role in payload

      // prepare photo payload depending on platform
      File? photoFile;
      Uint8List? photoBytes;
      String? filename;
      if (_pickedXFile != null) {
        if (kIsWeb) {
          photoBytes = await _pickedXFile!.readAsBytes();
          filename = _pickedXFile!.name;
        } else {
          photoFile = File(_pickedXFile!.path);
          filename = p.basename(photoFile.path);
        }
      }

      bool ok = false;
      if (kIsWeb) {
        ok = await AuthService.updateProfileWithBytes(
          nom: _nomCtrl.text.trim(),
          prenom: _prenomCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          photoBytes: photoBytes,
          filename: filename,
          extraFields: extra,
        );
      } else {
        ok = await AuthService.updateProfile(
          nom: _nomCtrl.text.trim(),
          prenom: _prenomCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          photoFile: photoFile,
          extraFields: extra,
        );
      }

      if (ok) {
        // fetch fresh profile to compute diff vs original snapshot
        final fresh = await AuthService.getProfile();
        if (fresh != null) {
          final changes = _computeProfileDiffLocal(_originalProfile, fresh);
          if (changes.isNotEmpty) {
            final now = DateTime.now().toIso8601String();
            final entries = changes
                .map((c) => {
                      'text': 'Profil mis à jour: $c',
                      'timestamp': now,
                      'type': 'profile_change',
                      'meta': {'change': c}
                    })
                .toList();

            // Try to persist to server first, fallback to local if posting fails
            final List<Map<String, dynamic>> toStoreLocally = [];
            for (final e in entries) {
              final posted = await AuthService.postActivity(e);
              if (!posted) toStoreLocally.add(e);
            }
            if (toStoreLocally.isNotEmpty) {
              await _storeLocalActivities(toStoreLocally);
            }

            // mark profile_updated to trigger home refresh behavior
            await SecureStorage.write('profile_updated', 'true');
          }
        }

        if (!mounted) return true;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profil mis à jour')));
        // navigate back to home so UserHome will run its load logic and consume stored activities
        if (mounted) context.go('/user-home');
        setState(() => _saving = false);
        return true;
      } else {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Échec de la mise à jour')));
      }
    } catch (e, st) {
      debugPrint('Profile update error: $e\n$st');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Erreur réseau lors de la mise à jour')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    return false;
  }

  Widget _avatarPreview() {
    if (_pickedXFile != null) {
      if (kIsWeb && _pickedBytes != null) {
        return CircleAvatar(
            radius: 40,
            backgroundImage: MemoryImage(_pickedBytes!),
            backgroundColor: Colors.grey.shade100);
      }
      return CircleAvatar(
          radius: 40,
          backgroundImage: FileImage(File(_pickedXFile!.path)),
          backgroundColor: Colors.grey.shade100);
    }

    final photoPath = _profile?['photo'] as String?;
    if (photoPath != null && photoPath.isNotEmpty) {
      final url = photoPath.startsWith('http')
          ? photoPath
          : _absolutePhotoUrl(photoPath);
      return CircleAvatar(
          radius: 40,
          backgroundImage: NetworkImage(url),
          backgroundColor: Colors.grey.shade100);
    }
    final initials = ((_prenomCtrl.text.isNotEmpty ? _prenomCtrl.text[0] : '') +
            (_nomCtrl.text.isNotEmpty ? _nomCtrl.text[0] : ''))
        .toUpperCase();
    return CircleAvatar(
        radius: 40,
        backgroundColor: Colors.blue.shade700,
        child: Text(initials.isNotEmpty ? initials : 'U',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)));
  }

  String _absolutePhotoUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final apiBase = AuthService.apiBase;
    const apiSuffix = '/api/v1';
    String root = apiBase;
    if (apiBase.endsWith(apiSuffix))
      root = apiBase.substring(0, apiBase.length - apiSuffix.length);
    return '$root${path.startsWith('/') ? '' : '/'}$path';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier mon profil'),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () async {
                    await _submit();
                  },
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Enregistrer',
                    style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Row(children: [
                        _avatarPreview(),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              TextFormField(
                                  controller: _prenomCtrl,
                                  decoration: const InputDecoration(
                                      labelText: 'Prénom'),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'Requis'
                                          : null),
                              const SizedBox(height: 8),
                              TextFormField(
                                  controller: _nomCtrl,
                                  decoration:
                                      const InputDecoration(labelText: 'Nom'),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'Requis'
                                          : null),
                            ])),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo, size: 18),
                            label: const Text('Galerie',
                                style: TextStyle(fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              minimumSize: const Size(0, 40),
                              elevation: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt, size: 18),
                            label: const Text('Caméra',
                                style: TextStyle(fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              minimumSize: const Size(0, 40),
                              elevation: 2,
                            ),
                          ),
                        ),
                        if (_pickedXFile != null) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 40,
                            child: OutlinedButton(
                              onPressed: () => setState(() {
                                _pickedXFile = null;
                                _pickedBytes = null;
                              }),
                              child: const Text('Annuler image',
                                  style: TextStyle(fontSize: 14)),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                minimumSize: const Size(0, 40),
                              ),
                            ),
                          ),
                        ]
                      ]),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requis'
                              : (!_validateEmail(v.trim()))
                                  ? 'Email invalide'
                                  : null),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: _telephoneCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Téléphone'),
                          keyboardType: TextInputType.phone),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: DropdownButtonFormField<String>(
                                value: _sexe,
                                decoration:
                                    const InputDecoration(labelText: 'Sexe'),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'M', child: Text('Masculin')),
                                  DropdownMenuItem(
                                      value: 'F', child: Text('Féminin'))
                                ],
                                onChanged: (v) => setState(() => _sexe = v))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: DropdownButtonFormField<String>(
                                value: _situation,
                                decoration: const InputDecoration(
                                    labelText: 'Situation'),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'celibataire',
                                      child: Text('Célibataire')),
                                  DropdownMenuItem(
                                      value: 'marie', child: Text('Marié(e)')),
                                  DropdownMenuItem(
                                      value: 'veuf', child: Text('Veuf(ve)')),
                                  DropdownMenuItem(
                                      value: 'divorce',
                                      child: Text('Divorcé(e)'))
                                ],
                                onChanged: (v) =>
                                    setState(() => _situation = v))),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextFormField(
                                readOnly: true,
                                decoration: InputDecoration(
                                    labelText: 'Date de naissance',
                                    hintText: _dateNaissance == null
                                        ? ''
                                        : _dateNaissance!
                                            .toIso8601String()
                                            .split('T')
                                            .first),
                                onTap: _pickDate)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: TextFormField(
                                controller: _lieuNaissCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Lieu de naissance'))),
                      ]),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: _cinNumeroCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Numéro CIN')),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: _cinDateCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Date délivrance CIN')),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextFormField(
                                controller: _adresseCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Adresse'))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('Nombre d\'enfants'),
                              const SizedBox(height: 6),
                              Row(children: [
                                IconButton(
                                    icon: const Icon(Icons.remove),
                                    onPressed: _nombreEnfants > 0
                                        ? () => setState(() => _nombreEnfants--)
                                        : null),
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0),
                                    child: Text('$_nombreEnfants',
                                        style: const TextStyle(fontSize: 16))),
                                IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: () =>
                                        setState(() => _nombreEnfants++)),
                              ]),
                            ])),
                      ]),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 140,
                            height: 44,
                            child: ElevatedButton.icon(
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save, size: 18),
                              label: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Text('Sauvegarder',
                                      style: TextStyle(fontSize: 14))),
                              onPressed: _saving
                                  ? null
                                  : () async {
                                      final ok = await _submit();
                                      if (!ok && mounted)
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Échec de la mise à jour')));
                                    },
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                elevation: 2,
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 140,
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : () => context.pop(),
                              icon: const Icon(Icons.close, size: 18),
                              label: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Text('Annuler',
                                      style: TextStyle(fontSize: 14))),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                side: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.12)),
                                foregroundColor:
                                    Theme.of(context).colorScheme.onSurface,
                                backgroundColor: Colors.transparent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
