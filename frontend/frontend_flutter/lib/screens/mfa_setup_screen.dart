import 'dart:convert';
import 'package:flutter/services.dart';
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
  String? qrBase64;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadProvisioningData();
  }

  Future<void> _loadProvisioningData() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await AuthService.setupMFA();
      debugPrint('[MFASetup] setupMFA result keys: ${data?.keys}');
      setState(() {
        provisioningUri = data?['provisioning_uri'] as String?;
        qrBase64 = data?['qr_base64'] as String?;
        loading = false;
      });
      debugPrint('[MFASetup] provisioningUri: $provisioningUri');
      debugPrint('[MFASetup] qrBase64 length: ${qrBase64?.length}');
    } catch (e, st) {
      debugPrint('[MFASetup] error: $e\n$st');
      setState(() {
        error = "Impossible de charger le QR code. Réessaie.";
        loading = false;
      });
    }
  }

  Widget _buildQr() {
    if (qrBase64 != null && qrBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(qrBase64!);
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          padding: const EdgeInsets.all(12),
          child: Image.memory(bytes, width: 220, height: 220),
        );
      } catch (e) {
        debugPrint('[MFASetup] base64 decode failed: $e');
      }
    }
    if (provisioningUri != null && provisioningUri!.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        padding: const EdgeInsets.all(12),
        child: QrImageView(
          data: provisioningUri!,
          version: QrVersions.auto,
          size: 220,
          backgroundColor: Colors.white,
        ),
      );
    }
    return const Text(
      "QR code indisponible. Réessaie plus tard.",
      style: TextStyle(color: Colors.red),
      textAlign: TextAlign.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Configurer l’authentification MFA")),
      body: RefreshIndicator(
        onRefresh: _loadProvisioningData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      "Scanne ce QR code avec Google Authenticator (ou Authy).",
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (loading)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      _buildQr(),
                      const SizedBox(height: 16),
                      if (provisioningUri != null &&
                          provisioningUri!.isNotEmpty)
                        Column(
                          children: [
                            const Text(
                              "Si l’appareil ne scanne pas, copie l'URI ci-dessous :",
                              style: TextStyle(
                                  fontSize: 13, color: Colors.black54),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.black12),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                provisioningUri!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.copy),
                                  label: const Text("Copier"),
                                  onPressed: () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: provisioningUri!));
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text("URI copié")),
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  label: const Text("Rafraîchir"),
                                  onPressed: _loadProvisioningData,
                                ),
                              ],
                            ),
                          ],
                        ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(error!, style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.lock),
              label: const Text("Continuer vers la vérification du code"),
              onPressed: () => context.go('/mfa-verify'),
            ),
          ],
        ),
      ),
    );
  }
}
