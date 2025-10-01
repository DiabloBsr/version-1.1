// lib/screens/support_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({Key? key}) : super(key: key);

  static const String _supportEmail = 'support@example.com';
  static const String _supportPhone = '+261 20 22 225 22';
  static const String _faqText = '''
Questions fréquentes

1) Comment récupérer mon mot de passe ?
   - Utilisez "Mot de passe oublié" sur l'écran de connexion pour recevoir un email de réinitialisation.

2) Je ne reçois pas l'OTP (code) ?
   - Vérifiez le dossier spam, la validité de l'email/numéro et réessayez. Si le problème persiste, contactez le support.

3) Comment modifier ma photo de profil ?
   - Allez sur "Modifier mon profil", choisissez Galerie ou Caméra puis sauvegardez.

4) Que faire en cas d'erreur réseau ?
   - Vérifiez votre connexion, réessayez plus tard et utilisez la fonction "Rafraîchir" du tableau de bord.

5) Où trouver mes informations de compte ?
   - Dans l'écran Profil ou Accueil vous trouverez nom, email et rôle.
''';

  void _copyToClipboard(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copié dans le presse-papiers')),
    );
  }

  void _showContactActionSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: Text('Email: $_supportEmail'),
              onTap: () {
                Navigator.of(ctx).pop();
                _copyToClipboard(context, 'Email', _supportEmail);
              },
            ),
            ListTile(
              leading: const Icon(Icons.phone),
              title: Text('Téléphone: $_supportPhone'),
              onTap: () {
                Navigator.of(ctx).pop();
                _copyToClipboard(context, 'Téléphone', _supportPhone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Fermer'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor =
        (theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onBackground)
            .withOpacity(0.9);

    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Row(children: [
                const Icon(Icons.support_agent_outlined,
                    size: 36, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Besoin d’aide ?',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                            'Contactez notre équipe de support pour toute question ou incident.',
                            style: TextStyle(color: textColor)),
                      ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showContactActionSheet(context),
              icon: const Icon(Icons.contact_support),
              label: const Text('Contacter le support'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  _copyToClipboard(context, 'Email', _supportEmail),
              icon: const Icon(Icons.email),
              label: const Text('Copier l’email du support'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  _copyToClipboard(context, 'Téléphone', _supportPhone),
              icon: const Icon(Icons.phone),
              label: const Text('Copier le téléphone'),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('FAQ',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text(_faqText, style: TextStyle(color: textColor)),
                  ]),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Retour'),
            ),
          ]),
        ),
      ),
    );
  }
}
