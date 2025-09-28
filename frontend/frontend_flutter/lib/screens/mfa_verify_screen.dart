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

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _submitOtp() async {
    if (_isLoading) return;
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      _showError("Le code doit contenir 6 chiffres.");
      return;
    }

    setState(() => _isLoading = true);
    final result = await AuthService.verifyMFA(otp);
    setState(() => _isLoading = false);

    debugPrint('[MFAVerify] verifyMFA result: $result');

    if (!mounted) return;

    if (result['success'] == true) {
      final auth = AuthProvider.of(context);

      // store tokens if present (support multiple key names)
      final access =
          (result['access'] as String?) ?? (result['access_token'] as String?);
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
            '[MFAVerify] no tokens in response; assume tokens already present or saved by AuthService');
      }

      // update MFA flags and role in AuthState
      debugPrint('[MFAVerify] setting otpVerified=true');
      await auth.setOtpVerified(true);

      debugPrint('[MFAVerify] setting mfaEnabled=true');
      await auth.setMfaEnabled(true);

      final apiRole = (result['role'] as String?)?.toLowerCase();
      if (apiRole != null && apiRole.isNotEmpty) {
        debugPrint('[MFAVerify] setting role from API: $apiRole');
        await auth.setRole(apiRole);
      } else {
        debugPrint(
            '[MFAVerify] API returned no role; keeping existing AuthState.role=${auth.role}');
      }

      // Allow GoRouter to re-evaluate using the authoritative AuthState.
      // Navigate to a neutral route ('/') and let router.redirect send the user to the correct page.
      await Future.delayed(const Duration(milliseconds: 50));
      debugPrint(
          '[MFAVerify] triggering router re-evaluation by navigating to root');
      context.go('/');
    } else {
      _showError(result['error']?.toString() ?? "Code OTP invalide ou expiré.");
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Vérification du code")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "Entre le code OTP à 6 chiffres généré par ton application MFA.",
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofocus: true,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: "Code OTP",
                border: OutlineInputBorder(),
                counterText: "",
              ),
              onSubmitted: (_) => _submitOtp(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.verified),
                label: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Vérifier"),
                onPressed: _isLoading ? null : _submitOtp,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.qr_code),
              label: const Text("Retour à l’étape QR"),
              onPressed: () => context.go('/mfa-setup'),
            ),
          ],
        ),
      ),
    );
  }
}
