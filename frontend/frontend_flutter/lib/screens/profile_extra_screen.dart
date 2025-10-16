import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../utils/secure_storage.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';

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
  DateTime? cinIssueDate;
  String? sexe;
  bool loading = false;
  bool _isHovering = false;

  String? email;
  String? username;
  String? firstName;
  String? lastName;
  String? _pendingPassword;
  String? errorText;

  String get apiBase => UserService.baseUrl.replaceAll(RegExp(r'/$'), '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFromRoute());
  }

  Future<void> _initFromRoute() async {
    if (!mounted) return;
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
      }

      _pendingPassword = await SecureStorage.read('pending_password');
      if (!mounted) return;
      setState(() {});
    } catch (e, st) {
      debugPrint('ProfileExtra init error: $e\n$st');
    }
  }

  @override
  void dispose() {
    phoneCtrl.dispose();
    lieuCtrl.dispose();
    cinCtrl.dispose();
    adresseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool forBirth}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          forBirth ? now.subtract(const Duration(days: 365 * 25)) : now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        if (forBirth) {
          birthDate = picked;
        } else {
          cinIssueDate = picked;
        }
      });
    }
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
    final uri = Uri.parse('$apiBase/profiles/');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $accessToken';
    profilePayload.forEach((k, v) {
      if (v != null) req.fields[k] = v.toString();
    });
    final streamed = await req.send();
    return await http.Response.fromStream(streamed);
  }

  Future<void> submitExtra() async {
    if (loading) return;
    setState(() {
      errorText = null;
      loading = true;
    });

    final pendingPwd = _pendingPassword;

    if (email == null || email!.isEmpty) {
      if (!mounted) return;
      setState(() {
        errorText = 'Email manquant';
        loading = false;
      });
      return;
    }
    if (username == null || username!.isEmpty) {
      if (!mounted) return;
      setState(() {
        errorText = 'Nom d\'utilisateur manquant';
        loading = false;
      });
      return;
    }
    if (pendingPwd == null || pendingPwd.isEmpty) {
      if (!mounted) return;
      setState(() {
        errorText = 'Mot de passe manquant, revenez à l\'inscription';
        loading = false;
      });
      return;
    }

    final anyProfileField = phoneCtrl.text.isNotEmpty ||
        lieuCtrl.text.isNotEmpty ||
        cinCtrl.text.isNotEmpty ||
        adresseCtrl.text.isNotEmpty ||
        birthDate != null ||
        cinIssueDate != null ||
        (sexe != null && sexe!.isNotEmpty);
    if (!anyProfileField) {
      if (!mounted) return;
      setState(() {
        errorText = 'Complétez au moins un champ de profil';
        loading = false;
      });
      return;
    }

    final userPayload = <String, dynamic>{
      'email': email,
      'username': username,
      'password': pendingPwd,
      if (firstName != null && firstName!.isNotEmpty) 'first_name': firstName,
      if (lastName != null && lastName!.isNotEmpty) 'last_name': lastName,
    };

    // Profile payload: only profile fields, omit email/username and omit role
    final profilePayload = <String, dynamic>{
      if (phoneCtrl.text.isNotEmpty) 'telephone': phoneCtrl.text.trim(),
      if (birthDate != null)
        'date_naissance': birthDate!.toIso8601String().split('T').first,
      if (lieuCtrl.text.isNotEmpty) 'lieu_naissance': lieuCtrl.text.trim(),
      if (cinCtrl.text.isNotEmpty) 'cin_numero': cinCtrl.text.trim(),
      if (cinIssueDate != null)
        'cin_date_delivrance': cinIssueDate!.toIso8601String().split('T').first,
      if (adresseCtrl.text.isNotEmpty) 'adresse': adresseCtrl.text.trim(),
      if (sexe != null && sexe!.isNotEmpty) 'sexe': sexe,
    };

    debugPrint('profilePayload to send: ${jsonEncode(profilePayload)}');

    try {
      // Create user
      final userResp = await http.post(
        Uri.parse('$apiBase/auth/users/'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: jsonEncode(userPayload),
      );

      if (!mounted) return;
      debugPrint(
          'create user status=${userResp.statusCode} body=${userResp.body}');

      if (userResp.statusCode != 201 && userResp.statusCode != 200) {
        String serverMsg = userResp.body.isNotEmpty
            ? userResp.body
            : 'Erreur création utilisateur';
        try {
          final parsed = jsonDecode(userResp.body);
          if (parsed is Map) {
            final parts = <String>[];
            parsed.forEach((k, v) {
              if (v is List)
                parts.add('$k: ${v.join(", ")}');
              else
                parts.add('$k: $v');
            });
            if (parts.isNotEmpty) serverMsg = parts.join(' ; ');
          }
        } catch (_) {}
        await SecureStorage.write(
            'pending_profile', jsonEncode(profilePayload));
        if (!mounted) return;
        setState(() {
          errorText = 'Erreur création utilisateur: $serverMsg';
          loading = false;
        });
        return;
      }

      // user created - delete pending_password
      await SecureStorage.delete('pending_password');
      _pendingPassword = null;

      // Try login (AuthService.login expected to exist)
      String? accessToken;
      try {
        final loginResp =
            await AuthService.login((email ?? username)!, pendingPwd);
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

      // Fallback token endpoint
      if (accessToken == null) {
        try {
          final tokenResp = await http.post(
            Uri.parse('$apiBase/token/'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: jsonEncode({'email': email, 'password': pendingPwd}),
          );
          if (!mounted) return;
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

      // Create profile if token available
      if (accessToken != null) {
        final profileResp =
            await _postProfileMultipart(accessToken, profilePayload);
        if (!mounted) return;
        debugPrint(
            'profile create multipart status=${profileResp.statusCode} body=${profileResp.body}');

        if (profileResp.statusCode == 201 || profileResp.statusCode == 200) {
          await SecureStorage.write('email', email!);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Inscription complète, profil créé.')));
          if (!mounted) return;
          context.go('/');
          return;
        } else {
          await SecureStorage.write(
              'pending_profile', jsonEncode(profilePayload));
          if (!mounted) return;
          setState(() {
            errorText =
                'Profil non créé (server ${profileResp.statusCode}); sauvegardé localement.';
            loading = false;
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Profil sauvegardé pour synchronisation ultérieure.')));
          if (!mounted) return;
          context.go('/');
          return;
        }
      } else {
        await SecureStorage.write(
            'pending_profile', jsonEncode(profilePayload));
        if (!mounted) return;
        setState(() {
          errorText =
              'Inscription créée, mais authentification automatique impossible. Profil sauvegardé localement.';
          loading = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Inscription faite. Profil sauvegardé localement.')));
        if (!mounted) return;
        context.go('/');
        return;
      }
    } catch (e, st) {
      debugPrint('submitExtra exception: $e\n$st');
      await SecureStorage.write('pending_profile', jsonEncode(profilePayload));
      if (!mounted) return;
      setState(() {
        errorText = 'Erreur réseau ou serveur: $e';
        loading = false;
      });
    } finally {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Widget _headerCard() {
    // Affiche l'email et le nom d'utilisateur en haut si disponibles
    return Card(
      color: Colors.grey.shade100,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (email != null && email!.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.email, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Email : $email',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
          if (username != null && username!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Nom d\'utilisateur : $username')),
                ],
              ),
            ),
        ]),
      ),
    );
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
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save,
                            key: ValueKey('icon'),
                            size: 18,
                            color: Colors.white),
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

  Widget _dateDisplay(String label, DateTime? date, VoidCallback onPick) {
    return InkWell(
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          label: Text(label),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date == null
                    ? ''
                    : date.toLocal().toIso8601String().split('T').first,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.calendar_today, size: 18),
              onPressed: onPick,
            ),
          ],
        ),
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
                          (username != null && username!.isNotEmpty))
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
                                  decoration:
                                      _inputDecoration(label: 'Téléphone'))),
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
                              onChanged: (v) {
                                if (!mounted) return;
                                setState(() => sexe = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Date of birth (left) and Place of birth (right) side by side
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: _dateDisplay('Date de naissance', birthDate,
                                () => _pickDate(forBirth: true)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                                controller: lieuCtrl,
                                decoration: _inputDecoration(
                                    label: 'Lieu de naissance')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // CIN number and CIN issue date side by side (number left, issue date right)
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                                controller: cinCtrl,
                                decoration:
                                    _inputDecoration(label: 'Numéro CIN')),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: _dateDisplay('Date délivrance CIN',
                                cinIssueDate, () => _pickDate(forBirth: false)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: adresseCtrl,
                          decoration: _inputDecoration(label: 'Adresse'),
                          maxLines: 3),
                      const SizedBox(height: 16),
                      _styledActionButton(),
                      const SizedBox(height: 12),
                      TextButton(
                          onPressed: () {
                            if (mounted) context.go('/');
                          },
                          child: const Text('Annuler')),
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
