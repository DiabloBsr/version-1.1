import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/auth_service.dart';

class MFASetupScreen extends StatefulWidget {
  const MFASetupScreen({super.key});

  @override
  State<MFASetupScreen> createState() => _MFASetupScreenState();
}

class _MFASetupScreenState extends State<MFASetupScreen> {
  String? provisioningUri;

  @override
  void initState() {
    super.initState();
    _loadProvisioningUri();
  }

  Future<void> _loadProvisioningUri() async {
    final uri = await AuthService.setupMFA();
    setState(() => provisioningUri = uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Configurer MFA")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: provisioningUri == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Scanne ce QR code dans Google Authenticator ou Authy :",
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  QrImageView(
                    data: provisioningUri!,
                    version: QrVersions.auto,
                    size: 200.0,
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.lock),
                    label: const Text("Continuer vers la vérification OTP"),
                    onPressed: () {
                      context.push('/mfa-verify');
                    },
                  ),
                ],
              ),
      ),
    );
  }
}
