import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../auth_provider.dart';

class MFAScreen extends StatefulWidget {
  const MFAScreen({super.key});

  @override
  State<MFAScreen> createState() => _MFAScreenState();
}

class _MFAScreenState extends State<MFAScreen> {
  final otpCtrl = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    otpCtrl.dispose();
    super.dispose();
  }

  Future<void> handleVerify() async {
    setState(() => loading = true);
    final authState = AuthProvider.of(context);

    final result = await AuthService.verifyMFA(otpCtrl.text.trim());
    if (!mounted) return;
    setState(() => loading = false);

    if (result['success'] == true) {
      authState.setOtpVerified(true);
      context.go('/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['error'] ?? 'OTP invalide'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vérification MFA')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: otpCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Code OTP'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: loading ? null : handleVerify,
              child: loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Vérifier'),
            ),
          ],
        ),
      ),
    );
  }
}
