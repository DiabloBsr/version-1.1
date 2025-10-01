// lib/screens/mfa_verify_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../auth_provider.dart';
import '../utils/secure_storage.dart';

class MFAVerifyScreen extends StatefulWidget {
  const MFAVerifyScreen({super.key});

  @override
  State<MFAVerifyScreen> createState() => _MFAVerifyScreenState();
}

class _MFAVerifyScreenState extends State<MFAVerifyScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isHovering = false;
  String? _errorText;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {Color bg = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: bg));
  }

  Future<void> _submitOtp() async {
    if (_isLoading) return;
    final otp = _otpController.text.trim();

    if (otp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
      setState(() => _errorText = "Le code doit contenir 6 chiffres.");
      _showSnack(_errorText!);
      return;
    }

    setState(() {
      _errorText = null;
      _isLoading = true;
    });

    try {
      final result = await AuthService.verifyMFA(otp);
      debugPrint('[MFAVerify] verifyMFA result: $result');

      if (!mounted) return;

      if (result['success'] == true) {
        final auth = AuthProvider.of(context);

        final access = (result['access'] as String?) ??
            (result['access_token'] as String?);
        final refresh = (result['refresh'] as String?) ??
            (result['refresh_token'] as String?);

        if (access != null && refresh != null) {
          debugPrint('[MFAVerify] saving tokens to AuthState');
          await auth.setTokens(access, refresh);
          final stored = await SecureStorage.read('access');
          debugPrint(
              '[MFAVerify] SecureStorage access after setTokens: ${stored != null ? stored.substring(0, 10) + "..." : "null"}');
        } else {
          debugPrint(
              '[MFAVerify] no tokens in response; assume existing tokens');
        }

        await auth.setOtpVerified(true);
        await auth.setMfaEnabled(true);

        final apiRole = (result['role'] as String?)?.toLowerCase();
        if (apiRole != null && apiRole.isNotEmpty) {
          await auth.setRole(apiRole);
        }

        // brief delay to let state settle, then navigate to root for router re-eval
        await Future.delayed(const Duration(milliseconds: 50));
        context.go('/');
      } else {
        final msg =
            result['error']?.toString() ?? "Code OTP invalide ou expiré.";
        setState(() => _errorText = msg);
        _showSnack(msg);
      }
    } catch (e, st) {
      debugPrint('[MFAVerify] unexpected error: $e\n$st');
      setState(() => _errorText = 'Erreur réseau. Réessaie.');
      _showSnack('Erreur réseau. Réessaie.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _otpField() {
    return TextField(
      controller: _otpController,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      autofocus: true,
      maxLength: 6,
      decoration: InputDecoration(
        labelText: "Code OTP",
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        counterText: "",
      ),
      onSubmitted: (_) => _submitOtp(),
    );
  }

  Widget _styledSubmitButton() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.identity()..scale(_isHovering ? 1.02 : 1.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: _isHovering
              ? [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
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
            onTap: _isLoading ? null : _submitOtp,
            splashColor: Colors.white24,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                color: _isLoading
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
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(scale: anim, child: child)),
                    child: _isLoading
                        ? const SizedBox(
                            key: ValueKey('loader'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.verified,
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
                    child: Text(_isLoading ? 'Vérification...' : 'Vérifier'),
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
      appBar: AppBar(title: const Text("Vérification du code")),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 6),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)]),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 4))
                        ],
                      ),
                      child: const Center(
                          child: Icon(Icons.lock_clock,
                              color: Colors.white, size: 32)),
                    ),
                    const SizedBox(height: 12),
                    const Text('Vérifie ton code OTP',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text(
                        'Saisis le code à 6 chiffres généré par ton application d’authentification',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 14),
                    _otpField(),
                    if (_errorText != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade100)),
                        child: Row(children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(_errorText!,
                                  style: TextStyle(color: Colors.red.shade700)))
                        ]),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: _styledSubmitButton()),
                    ]),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      icon: const Icon(Icons.qr_code),
                      label: const Text("Retour à l’étape QR"),
                      onPressed: () => context.go('/mfa-setup'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
