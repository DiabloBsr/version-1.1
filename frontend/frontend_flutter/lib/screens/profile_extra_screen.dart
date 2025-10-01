// lib/screens/profile_extra_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../utils/secure_storage.dart';

class ProfileExtraScreen extends StatefulWidget {
  const ProfileExtraScreen({super.key});

  @override
  State<ProfileExtraScreen> createState() => _ProfileExtraScreenState();
}

class _ProfileExtraScreenState extends State<ProfileExtraScreen> {
  final phoneCtrl = TextEditingController();
  final lieuCtrl = TextEditingController();
  final cinCtrl = TextEditingController();
  final adresseCtrl = TextEditingController();

  DateTime? birthDate;
  String? sexe;
  bool loading = false;
  bool _isHovering = false;

  String? email;
  String? username;
  String? firstName;
  String? lastName;
  String? _pendingPassword;
  String? errorText;

  final String baseUrl = 'http://127.0.0.1:8000'; // adapte si nécessaire

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final routeState = GoRouterState.of(context);
        final dynamic rawExtra = routeState.extra;
        if (rawExtra is Map<String, dynamic>) {
          email = rawExtra['email'] as String?;
          username = rawExtra['username'] as String?;
          firstName = rawExtra['first_name'] as String?;
          lastName = rawExtra['last_name'] as String?;
        } else if (rawExtra is Map) {
          email = rawExtra['email']?.toString();
          username = rawExtra['username']?.toString();
          firstName = rawExtra['first_name']?.toString();
          lastName = rawExtra['last_name']?.toString();
        } else {
          debugPrint(
              'ProfileExtra init - no extra or unexpected type: ${rawExtra.runtimeType}');
        }

        _pendingPassword = await SecureStorage.read('pending_password');
        debugPrint(
            'ProfileExtra init - extra: $rawExtra, pending_password_present: ${_pendingPassword != null && _pendingPassword!.isNotEmpty}');
      } catch (e, st) {
        debugPrint('ProfileExtra init error: $e\n$st');
      } finally {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    phoneCtrl.dispose();
    lieuCtrl.dispose();
    cinCtrl.dispose();
    adresseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => birthDate = picked);
  }

  InputDecoration _inputDecoration({required String label}) {
    return InputDecoration(
      label: Text(label),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  Future<http.Response> _postProfileMultipart(
      String accessToken, Map<String, dynamic> profilePayload) async {
    final uri = Uri.parse('$baseUrl/api/v1/profiles/');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $accessToken';
    // add fields as strings (exclude nulls)
    profilePayload.forEach((k, v) {
      if (v != null) req.fields[k] = v.toString();
    });

    // If you want to attach a photo from bytes, uncomment and provide bytes
    // final Uint8List? imageBytes = ...;
    // if (imageBytes != null) {
    //   req.files.add(http.MultipartFile.fromBytes('photo', imageBytes, filename: 'photo.jpg'));
    // }

    final streamed = await req.send();
    return await http.Response.fromStream(streamed);
  }

  Future<void> submitExtra() async {
    setState(() => errorText = null);
    final missing = <String>[];
    final pendingPwd = _pendingPassword;

    if (email == null || email!.isEmpty) missing.add('email');
    if (username == null || username!.isEmpty) missing.add('username');
    if (pendingPwd == null || pendingPwd.isEmpty)
      missing.add('pending_password');

    final anyProfileField = phoneCtrl.text.isNotEmpty ||
        lieuCtrl.text.isNotEmpty ||
        cinCtrl.text.isNotEmpty ||
        adresseCtrl.text.isNotEmpty ||
        birthDate != null ||
        (sexe != null && sexe!.isNotEmpty);
    if (!anyProfileField) missing.add('aucun_champ_de_profil_rempli');

    if (missing.isNotEmpty) {
      final msg = 'Données manquantes: ${missing.join(', ')}';
      debugPrint(msg);
      setState(() => errorText = msg);
      return;
    }

    if (loading) return;
    setState(() => loading = true);

    final userPayload = <String, dynamic>{
      'email': email,
      'username': username,
      'password': pendingPwd,
      if (firstName != null && firstName!.isNotEmpty) 'first_name': firstName,
      if (lastName != null && lastName!.isNotEmpty) 'last_name': lastName,
    };

    final profilePayload = <String, dynamic>{
      if (firstName != null && firstName!.isNotEmpty) 'prenom': firstName,
      if (lastName != null && lastName!.isNotEmpty) 'nom': lastName,
      if (phoneCtrl.text.isNotEmpty) 'telephone': phoneCtrl.text.trim(),
      if (lieuCtrl.text.isNotEmpty) 'lieu_naissance': lieuCtrl.text.trim(),
      if (cinCtrl.text.isNotEmpty) 'cin_numero': cinCtrl.text.trim(),
      if (adresseCtrl.text.isNotEmpty) 'adresse': adresseCtrl.text.trim(),
      // CORRECTION: send only YYYY-MM-DD (backend expects this format)
      if (birthDate != null)
        'date_naissance': birthDate!.toIso8601String().split('T').first,
      if (sexe != null && sexe!.isNotEmpty) 'sexe': sexe,
      if (email != null) 'email': email,
      if (username != null) 'username': username,
    };

    debugPrint('profilePayload to send: ${jsonEncode(profilePayload)}');

    try {
      // 1) Create user
      final userResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/users/'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: jsonEncode(userPayload),
      );

      debugPrint(
          'create user status=${userResp.statusCode} body=${userResp.body}');

      if (userResp.statusCode != 201 && userResp.statusCode != 200) {
        final err = userResp.body.isNotEmpty
            ? userResp.body
            : 'Erreur création utilisateur';
        setState(() => errorText = 'Erreur création utilisateur: $err');
        await SecureStorage.write(
            'pending_profile', jsonEncode(profilePayload));
        return;
      }

      // user created - remove pending password
      await SecureStorage.delete('pending_password');
      _pendingPassword = null;

      // 2) Login to get token via AuthService.login (preferred)
      String? accessToken;
      try {
        final loginResp =
            await AuthService.login((email ?? username)!, pendingPwd!);
        debugPrint('AuthService.login returned: $loginResp');
        accessToken = (loginResp['access'] as String?) ??
            (loginResp['access_token'] as String?) ??
            (loginResp['token'] as String?);
        final refresh = (loginResp['refresh'] as String?) ??
            (loginResp['refresh_token'] as String?);
        if (accessToken != null) {
          await SecureStorage.write('access', accessToken);
          if (refresh != null) await SecureStorage.write('refresh', refresh);
        }
      } catch (e) {
        debugPrint('AuthService.login failed: $e');
      }

      // fallback: try token endpoint common path if accessToken still null
      if (accessToken == null) {
        try {
          final tokenResp = await http.post(
            Uri.parse('$baseUrl/api/v1/token/'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: jsonEncode({'email': email, 'password': pendingPwd}),
          );
          debugPrint(
              'fallback token login status=${tokenResp.statusCode} body=${tokenResp.body}');
          if (tokenResp.statusCode == 200) {
            final parsed = jsonDecode(tokenResp.body) as Map<String, dynamic>;
            accessToken =
                parsed['access'] as String? ?? parsed['auth_token'] as String?;
            final refresh = parsed['refresh'] as String?;
            if (accessToken != null) {
              await SecureStorage.write('access', accessToken);
              if (refresh != null)
                await SecureStorage.write('refresh', refresh);
            }
          }
        } catch (e) {
          debugPrint('fallback token login exception: $e');
        }
      }

      // 3) If we have accessToken, send multipart/form-data to create profile
      if (accessToken != null) {
        final profileResp =
            await _postProfileMultipart(accessToken, profilePayload);
        debugPrint(
            'profile create multipart status=${profileResp.statusCode} body=${profileResp.body}');

        if (profileResp.statusCode == 201 || profileResp.statusCode == 200) {
          await SecureStorage.write('email', email!);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Inscription complète, profil créé.')));
          context.go('/');
          return;
        } else {
          // save pending profile and inform user
          await SecureStorage.write(
              'pending_profile', jsonEncode(profilePayload));
          setState(() => errorText =
              'Profil non créé (server ${profileResp.statusCode}); sauvegardé localement.');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Profil sauvegardé pour synchronisation ultérieure.')));
          context.go('/');
          return;
        }
      } else {
        // No token possible: save pending_profile
        await SecureStorage.write(
            'pending_profile', jsonEncode(profilePayload));
        setState(() => errorText =
            'Inscription créée, mais authentification automatique impossible. Profil sauvegardé localement.');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Inscription faite. Profil sauvegardé localement.')));
        context.go('/');
        return;
      }
    } catch (e, st) {
      debugPrint('submitExtra exception: $e\n$st');
      setState(() => errorText = 'Erreur réseau ou serveur: $e');
      await SecureStorage.write('pending_profile', jsonEncode(profilePayload));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _styledActionButton() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.identity()..scale(_isHovering ? 1.02 : 1.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: _isHovering
              ? [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: const Offset(0, 6))
                ]
              : [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: const Offset(0, 3))
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: loading ? null : submitExtra,
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
              decoration: BoxDecoration(
                color: loading
                    ? const Color.fromARGB(255, 40, 88, 185).withOpacity(0.8)
                    : (_isHovering
                        ? const Color.fromARGB(255, 23, 63, 150)
                        : const Color.fromARGB(255, 40, 88, 185)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(scale: anim, child: child)),
                    child: loading
                        ? const SizedBox(
                            key: ValueKey('loader'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(
                            Icons.save,
                            key: ValueKey('icon'),
                            size: 18,
                            color: Colors.white,
                          ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 160),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                    child: Text(loading
                        ? 'Enregistrement...'
                        : "Terminer l'inscription"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCard() {
    final fullName = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return Card(
      color: Colors.grey.shade100,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (email != null && email!.isNotEmpty) Text('📧 Email : $email'),
          if (fullName.isNotEmpty) Text('👤 Nom : $fullName'),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 6),
                      if ((email != null && email!.isNotEmpty) ||
                          (firstName != null && firstName!.isNotEmpty) ||
                          (lastName != null && lastName!.isNotEmpty))
                        _headerCard(),
                      const SizedBox(height: 6),
                      if (errorText != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: Colors.red.shade700, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(errorText!,
                                      style: TextStyle(
                                          color: Colors.red.shade700))),
                              IconButton(
                                  icon: Icon(Icons.close,
                                      color: Colors.red.shade200),
                                  onPressed: () =>
                                      setState(() => errorText = null)),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: _inputDecoration(label: 'Téléphone'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: sexe,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none),
                                label: const Text('Sexe'),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'M', child: Text('Masculin')),
                                DropdownMenuItem(
                                    value: 'F', child: Text('Féminin')),
                              ],
                              onChanged: (v) => setState(() => sexe = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: lieuCtrl,
                          decoration:
                              _inputDecoration(label: 'Lieu de naissance')),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: cinCtrl,
                          decoration: _inputDecoration(label: 'Numéro CIN')),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: adresseCtrl,
                          decoration: _inputDecoration(label: 'Adresse'),
                          maxLines: 3),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(birthDate == null
                            ? 'Date de naissance'
                            : 'Date: ${birthDate!.toLocal().toIso8601String().split("T").first}'),
                        trailing: IconButton(
                            icon: const Icon(Icons.calendar_today),
                            onPressed: _pickDate),
                      ),
                      const SizedBox(height: 16),
                      _styledActionButton(),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          context.go('/');
                        },
                        child: const Text('Annuler'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
