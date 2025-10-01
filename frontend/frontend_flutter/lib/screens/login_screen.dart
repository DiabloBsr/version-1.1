// lib/screens/login_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../auth_provider.dart';
import '../utils/secure_storage.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;
  bool obscure = true;
  String? errorText;
  bool _isHovering = false;

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    return regex.hasMatch(email);
  }

  Future<void> handleLogin() async {
    setState(() => errorText = null);

    final email = emailCtrl.text.trim();
    final password = passCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => errorText = 'Email et mot de passe sont obligatoires');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => errorText = 'Email invalide');
      return;
    }

    setState(() => loading = true);
    try {
      final response = await AuthService.login(email, password);
      debugPrint('[Login] login response: $response');

      if (response['success'] == true) {
        final auth = AuthProvider.of(context);

        final access = (response['access'] as String?) ??
            (response['access_token'] as String?);
        final refresh = (response['refresh'] as String?) ??
            (response['refresh_token'] as String?);

        if (access != null && refresh != null) {
          await auth.setTokens(access, refresh);
          final stored = await SecureStorage.read('access');
          debugPrint(
              '[Login] SecureStorage access after setTokens: ${stored != null ? stored.substring(0, 10) + "..." : "null"}');
        } else {
          debugPrint('[Login] login response contained no tokens');
        }

        Map<String, dynamic>? profile;
        try {
          profile = await AuthService.getProfile();
          debugPrint('[Login] profile fetch result: $profile');
        } catch (e) {
          debugPrint('[Login] profile fetch error: $e');
        }

        final storedRole = await SecureStorage.read('role');
        final storedEmail = await SecureStorage.read('email');
        final storedMfa = await SecureStorage.read('mfa_enabled');
        final storedOtp = await SecureStorage.read('otp_verified');

        if (profile != null) {
          final role = (profile['role'] as String?) ?? storedRole;
          final emailVal = (profile['user'] is Map)
              ? profile['user']['email'] as String?
              : storedEmail;
          final mfaEnabled =
              profile['mfa_enabled'] == true || storedMfa == 'true';
          final otp = profile['otp_verified'] == true ||
              profile['otp_verified'] == 'true' ||
              storedOtp == 'true';

          if (role != null) await auth.setRole(role);
          if (emailVal != null) await auth.setUserEmail(emailVal);
          await auth.setMfaEnabled(mfaEnabled);
          if (otp) await auth.setOtpVerified(true);
        } else {
          if (storedRole != null) await auth.setRole(storedRole);
          if (storedEmail != null) await auth.setUserEmail(storedEmail);
          await auth.setMfaEnabled(storedMfa == 'true');
          if (storedOtp == 'true') await auth.setOtpVerified(true);
        }

        if (!mounted) return;

        debugPrint(
            '[Login] auth.loggedIn=${auth.loggedIn}, otpVerified=${auth.otpVerified}, mfaEnabled=${auth.mfaEnabled}, role=${auth.role}');
        if (auth.loggedIn && auth.otpVerified) {
          final r = auth.role?.toLowerCase();
          if (r == 'admin') {
            context.go('/dashboard');
          } else if (r == 'user') {
            context.go('/user-home');
          } else {
            context.go('/home');
          }
        } else {
          if (auth.mfaEnabled == true) {
            context.go('/mfa-verify');
          } else {
            context.go('/mfa-setup');
          }
        }
      } else {
        String message = "Échec de connexion";
        if (response['error'] != null) {
          try {
            final error = jsonDecode(response['error']);
            if (error is Map && error.containsKey('detail')) {
              message = error['detail'];
            } else {
              message = error.toString();
            }
          } catch (_) {
            message = response['error'].toString();
          }
        }
        setState(() => errorText = message);
      }
    } catch (e, st) {
      debugPrint('[Login] unexpected error: $e\n$st');
      setState(() => errorText = 'Erreur réseau: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)]),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
            ],
          ),
          child: const Center(
              child: Icon(Icons.lock_outline, color: Colors.white, size: 40)),
        ),
        const SizedBox(height: 12),
        const Text('Bienvenue',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Connectez-vous pour continuer',
            style: TextStyle(fontSize: 13, color: Colors.black54)),
      ],
    );
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

  Widget _styledLoginButton() {
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
            onTap: loading ? null : handleLogin,
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
              decoration: BoxDecoration(
                color: loading
                    ? const Color(0xFF4F46E5).withOpacity(0.8)
                    : (_isHovering
                        ? const Color(0xFF3B37C7)
                        : const Color(0xFF4F46E5)),
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
                            key: ValueKey('login_loader'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(
                            Icons.login,
                            key: ValueKey('login_icon'),
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
                    child: Text(loading ? 'Connexion...' : "Se connecter"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialButton(
      {required IconData icon, required String label, required Color color}) {
    return ElevatedButton.icon(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label pas encore implémenté')));
      },
      icon: Icon(icon, color: Colors.white, size: 18),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 2,
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLogo(),
                      const SizedBox(height: 20),
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
                                    setState(() => errorText = null),
                              )
                            ],
                          ),
                        ),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _fieldDecoration(label: 'Email'),
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        obscureText: obscure,
                        decoration: _fieldDecoration(
                          label: 'Mot de passe',
                          suffix: IconButton(
                            icon: Icon(
                                obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.black54),
                            onPressed: () => setState(() => obscure = !obscure),
                          ),
                        ),
                        onSubmitted: (_) => handleLogin(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                              onPressed: () => context.go('/forgot-password'),
                              child: const Text('Mot de passe oublié ?')),
                          TextButton(
                              onPressed: () => context.go('/register'),
                              child: const Text('Créer un compte')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _styledLoginButton(),
                      const SizedBox(height: 14),
                      Text('Ou se connecter avec',
                          style: TextStyle(color: Colors.grey.shade600)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _socialButton(
                              icon: Icons.apple,
                              label: 'Apple',
                              color: Colors.black),
                          const SizedBox(width: 12),
                          _socialButton(
                              icon: Icons.g_mobiledata,
                              label: 'Google',
                              color: Colors.redAccent),
                          const SizedBox(width: 12),
                          _socialButton(
                              icon: Icons.facebook,
                              label: 'Facebook',
                              color: Colors.blue),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('En continuant, vous acceptez nos conditions.',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12)),
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
