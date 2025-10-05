// lib/screens/mfa_setup_screen.dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/auth_service.dart';
import '../auth_provider.dart';

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
  bool _isHoveringPrimary = false;
  bool _isHoveringCopy = false;

  @override
  void initState() {
    super.initState();
    _loadProvisioningData();
  }

  Future<void> _loadProvisioningData() async {
    setState(() {
      loading = true;
      error = null;
      provisioningUri = null;
      qrBase64 = null;
    });
    try {
      final data = await AuthService.setupMFA();
      setState(() {
        provisioningUri = data?['provisioning_uri'] as String?;
        qrBase64 = data?['qr_base64'] as String?;
        loading = false;
      });
    } catch (e, st) {
      debugPrint('[MFASetup] error: $e\n$st');
      setState(() {
        error = "Impossible de charger le QR code. Réessaie.";
        loading = false;
      });
    }
  }

  Widget _buildQrCard(double size) {
    final boxDecoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.black12),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
      ],
    );

    if (loading) {
      return Container(
          width: size,
          height: size,
          decoration: boxDecoration,
          child: const Center(child: CircularProgressIndicator()));
    }

    if (qrBase64 != null && qrBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(qrBase64!);
        return Container(
            decoration: boxDecoration,
            padding: const EdgeInsets.all(8),
            child: Image.memory(bytes,
                width: size - 16, height: size - 16, fit: BoxFit.contain));
      } catch (e) {
        debugPrint('[MFASetup] base64 decode failed: $e');
      }
    }

    if (provisioningUri != null && provisioningUri!.isNotEmpty) {
      return Container(
        decoration: boxDecoration,
        padding: const EdgeInsets.all(8),
        child: QrImageView(
            data: provisioningUri!,
            version: QrVersions.auto,
            size: size - 16,
            backgroundColor: Colors.white),
      );
    }

    return Container(
        width: size,
        height: size,
        decoration: boxDecoration,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: const Text("QR indisponible",
            style: TextStyle(color: Colors.red), textAlign: TextAlign.center));
  }

  Widget _copyButton() {
    final isEnabled = provisioningUri != null && provisioningUri!.isNotEmpty;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringCopy = true),
      onExit: (_) => setState(() => _isHoveringCopy = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: Matrix4.identity()..scale(_isHoveringCopy ? 1.03 : 1.0),
        child: ElevatedButton.icon(
          onPressed: isEnabled
              ? () async {
                  final uri = provisioningUri!;
                  await Clipboard.setData(ClipboardData(text: uri));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("URI copié")));
                  }
                }
              : null,
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copier'),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isEnabled ? Colors.grey.shade100 : Colors.grey.shade200,
            foregroundColor: isEnabled ? Colors.black87 : Colors.black38,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }

  Widget _styledPrimaryButton(
      {required Widget child, required VoidCallback onTap}) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringPrimary = true),
      onExit: (_) => setState(() => _isHoveringPrimary = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.identity()..scale(_isHoveringPrimary ? 1.02 : 1.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: _isHoveringPrimary
              ? [
                  const BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 6))
                ]
              : [
                  const BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 3))
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            splashColor: Colors.white24,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                  color: _isHoveringPrimary
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(12)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _instructionsColumn() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Étapes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      const Text('1. Ouvre Google Authenticator ou Authy',
          style: TextStyle(fontSize: 14)),
      const SizedBox(height: 6),
      const Text('2. Sélectionne "Scanner un code" et scanne le QR',
          style: TextStyle(fontSize: 14)),
      const SizedBox(height: 6),
      const Text('3. Si le scan échoue, copie l’URI et ajoute‑la manuellement',
          style: TextStyle(fontSize: 14, color: Colors.black54)),
      const SizedBox(height: 10),
      if (error != null)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade100)),
          child: Row(children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child:
                    Text(error!, style: TextStyle(color: Colors.red.shade700)))
          ]),
        ),
      if (!loading &&
          provisioningUri != null &&
          provisioningUri!.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('URI de provisioning',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black12)),
          padding: const EdgeInsets.all(10),
          child: SelectableText(provisioningUri!,
              style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          _copyButton(),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _loadProvisioningData,
            icon: const Icon(Icons.refresh),
            label: const Text('Rafraîchir'),
            style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: Colors.grey.shade100,
                foregroundColor: Colors.black87,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
          )
        ]),
      ],
      const SizedBox(height: 8),
      Text(
          'Lorsque le QR est scanné, tu seras redirigé vers la vérification du code.',
          style: TextStyle(color: Colors.grey.shade600)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // Card height limit so primary button remains visible without heavy scrolling
    const double cardMaxHeight = 560;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: const Text("Configurer l’authentification MFA")),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              elevation: 12,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: cardMaxHeight),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                            gradient: LinearGradient(
                                colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)]),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: Offset(0, 4))
                            ]),
                        child: const Center(
                            child: Icon(Icons.phonelink_lock,
                                color: Colors.white, size: 32)),
                      ),
                      const SizedBox(height: 10),
                      const Text('Activer l’authentification à deux facteurs',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      const Text(
                          'Scanne le QR ou copie l’URI dans ton application d’authentification',
                          style: TextStyle(color: Colors.black54),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),

                      // Body: flexible area with limited height and internal scrolling if needed
                      Expanded(
                        child: LayoutBuilder(builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 560;
                          final qrSize = isWide ? 220.0 : 160.0;

                          // Left QR + small controls, Right instructions inside a scrollable area
                          final leftPart =
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            _buildQrCard(qrSize),
                            const SizedBox(height: 8),
                          ]);

                          final rightPart = SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: _instructionsColumn(),
                          );

                          if (isWide) {
                            return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Flexible(flex: 0, child: leftPart),
                                  const SizedBox(width: 14),
                                  Expanded(child: rightPart),
                                ]);
                          } else {
                            return Column(children: [
                              leftPart,
                              const SizedBox(height: 10),
                              rightPart,
                            ]);
                          }
                        }),
                      ),

                      const SizedBox(height: 12),

                      // Primary action is outside the scrollable region and always visible
                      _styledPrimaryButton(
                        onTap: () async {
                          try {
                            // optional backend finalization:
                            // await AuthService.completeMfaSetup();

                            // Use AuthProvider to update and notify the same AuthState used by the router
                            final authState = AuthProvider.of(context);
                            authState.setPendingLogin(true);

                            // deterministic navigation to verify screen
                            context.go('/mfa-verify');
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Erreur: $e')));
                            }
                          }
                        },
                        child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock, color: Colors.white, size: 18),
                              SizedBox(width: 10),
                              Text("Continuer vers la vérification",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ]),
                      ),

                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: () => context.go('/'),
                          child: const Text('Retour')),
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
