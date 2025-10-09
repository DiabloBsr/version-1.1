// lib/screens/register_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/secure_storage.dart';
import '../services/user_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final emailCtrl = TextEditingController();
  final usernameCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final firstCtrl = TextEditingController();
  final lastCtrl = TextEditingController();

  bool loading = false;
  bool obscure = true;
  String? errorText;
  bool _isHovering = false;

  @override
  void dispose() {
    emailCtrl.dispose();
    usernameCtrl.dispose();
    passCtrl.dispose();
    firstCtrl.dispose();
    lastCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    return regex.hasMatch(email);
  }

  bool _isStrongPassword(String password) {
    return password.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password) &&
        RegExp(r'[!@#\$&*~]').hasMatch(password);
  }

  // Simple similarity check: longest common substring normalized by max length.
  // Returns true if similarity ratio >= 0.45 (tunable).
  double _longestCommonSubstringRatio(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final la = a.length;
    final lb = b.length;
    // dynamic programming LCSUBSTR
    final List<List<int>> dp =
        List.generate(la + 1, (_) => List<int>.filled(lb + 1, 0));
    int longest = 0;
    for (int i = 1; i <= la; i++) {
      for (int j = 1; j <= lb; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
          if (dp[i][j] > longest) longest = dp[i][j];
        }
      }
    }
    final maxLen = la > lb ? la : lb;
    return maxLen == 0 ? 0.0 : longest / maxLen;
  }

  bool _isPasswordTooSimilar(String username, String password) {
    final u = username.trim().toLowerCase();
    final p = password.trim().toLowerCase();
    if (u.isEmpty || p.isEmpty) return false;
    // direct containment checks (very similar)
    if (u.length >= 3 && p.contains(u)) return true;
    if (p.length >= 3 && u.contains(p)) return true;
    // LCS ratio check
    final ratio = _longestCommonSubstringRatio(u, p);
    return ratio >= 0.45; // threshold: adjust if needed
  }

  Future<void> handleContinue() async {
    if (loading) return;
    if (!mounted) return;
    setState(() {
      errorText = null;
      loading = true;
    });

    final email = emailCtrl.text.trim();
    final username = usernameCtrl.text.trim();
    final password = passCtrl.text;

    if (email.isEmpty || username.isEmpty || password.isEmpty) {
      if (!mounted) return;
      setState(() {
        errorText = "Les champs marqués * sont obligatoires";
        loading = false;
      });
      return;
    }

    if (!_isValidEmail(email)) {
      if (!mounted) return;
      setState(() {
        errorText = "Email invalide";
        loading = false;
      });
      return;
    }

    if (!_isStrongPassword(password)) {
      if (!mounted) return;
      setState(() {
        errorText =
            "Mot de passe trop faible (min 8, 1 majuscule, 1 chiffre, 1 symbole)";
        loading = false;
      });
      return;
    }

    // New: reject if password is very similar to username
    if (_isPasswordTooSimilar(username, password)) {
      if (!mounted) return;
      setState(() {
        errorText =
            "Le mot de passe est trop similaire au nom d'utilisateur. Choisissez un mot de passe différent.";
        loading = false;
      });
      return;
    }

    try {
      // Vérification d'unicité côté register (avant redirection)
      final usernameTaken = await UserService.usernameExists(username);
      if (!mounted) return;
      if (usernameTaken) {
        setState(() {
          errorText =
              "Ce nom d'utilisateur est déjà utilisé. Veuillez en choisir un autre.";
          loading = false;
        });
        return;
      }

      final emailTaken = await UserService.emailExists(email);
      if (!mounted) return;
      if (emailTaken) {
        setState(() {
          errorText =
              "Cet email est déjà associé à un compte. Connectez-vous ou utilisez un autre email.";
          loading = false;
        });
        return;
      }

      // Tous les checks OK -> stocker le mot de passe et rediriger vers profile-extra
      await SecureStorage.write('pending_password', password);
      if (!mounted) return;

      final extra = <String, String>{
        'email': email,
        'username': username,
        if (firstCtrl.text.trim().isNotEmpty)
          'first_name': firstCtrl.text.trim(),
        if (lastCtrl.text.trim().isNotEmpty) 'last_name': lastCtrl.text.trim(),
      };

      if (!mounted) return;
      debugPrint(
          'RegisterScreen navigate -> /profile-extra with extra: $extra');
      try {
        context.go('/profile-extra', extra: extra);
      } catch (e, st) {
        debugPrint('Navigation to /profile-extra failed: $e\n$st');
        if (!mounted) return;
        setState(() {
          errorText = 'Navigation failed. Réessayez.';
        });
      }
    } on EndpointNotFoundException catch (_) {
      if (!mounted) return;
      setState(() {
        errorText =
            'Impossible de vérifier l’unicité : le serveur ne propose pas d’endpoint public de vérification. Contactez l’administrateur.';
        loading = false;
      });
    } on EndpointAuthRequiredException catch (_) {
      if (!mounted) return;
      setState(() {
        errorText =
            'Le serveur protège l’endpoint de vérification (401). Contactez l’administrateur ou activez une vérification côté serveur.';
        loading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        errorText =
            "Le serveur a mis trop de temps à répondre lors des vérifications. Réessayez.";
        loading = false;
      });
    } catch (e, st) {
      debugPrint('handleContinue error: $e\n$st');
      if (!mounted) return;
      setState(
          () => errorText = 'Erreur réseau ou serveur. Réessayez plus tard.');
    } finally {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  InputDecoration _fieldDecoration({required String label, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      suffixIcon: suffix,
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF06B6D4), Color(0xFF4F46E5)]),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))
            ],
          ),
          child: const Center(
              child: Icon(Icons.person_add, color: Colors.white, size: 34)),
        ),
        const SizedBox(height: 12),
        const Text('Créer un compte',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text('Commencez votre inscription en quelques étapes',
            style: TextStyle(fontSize: 13, color: Colors.black54)),
      ],
    );
  }

  Widget _styledActionButton() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
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
            onTap: loading ? null : handleContinue,
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
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
                        : const Icon(Icons.arrow_forward,
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
                    child: Text(loading ? 'Traitement...' : "S'inscrire"),
                  ),
                ],
              ),
            ),
          ),
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
              constraints: const BoxConstraints(maxWidth: 540),
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
                      _buildHeader(),
                      const SizedBox(height: 18),
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
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _fieldDecoration(label: 'Email *'),
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: usernameCtrl,
                        decoration:
                            _fieldDecoration(label: 'Nom d’utilisateur *'),
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        obscureText: obscure,
                        decoration: _fieldDecoration(
                          label: 'Mot de passe *',
                          suffix: IconButton(
                              icon: Icon(
                                  obscure
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.black54),
                              onPressed: () =>
                                  setState(() => obscure = !obscure)),
                        ),
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                              child: TextField(
                                  controller: firstCtrl,
                                  decoration:
                                      _fieldDecoration(label: 'Prénom'))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: TextField(
                                  controller: lastCtrl,
                                  decoration: _fieldDecoration(label: 'Nom'))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _styledActionButton(),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Déjà inscrit ?',
                              style: TextStyle(color: Colors.black54)),
                          TextButton(
                              onPressed: () => context.go('/login'),
                              child: const Text('Se connecter')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'En créant un compte, vous acceptez nos conditions et notre politique de confidentialité.',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12),
                        textAlign: TextAlign.center,
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
