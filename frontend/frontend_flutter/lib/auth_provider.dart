import 'package:flutter/widgets.dart';
import 'auth_state.dart';

/// AuthProvider expose AuthState via InheritedNotifier.
/// Tous les widgets qui appellent AuthProvider.of(context)
/// seront reconstruits quand AuthState.notifyListeners() est appelé.
class AuthProvider extends InheritedNotifier<AuthState> {
  const AuthProvider({
    required AuthState authState,
    required Widget child,
    Key? key,
  }) : super(key: key, notifier: authState, child: child);

  /// Accès obligatoire à AuthState. Lève une erreur si non trouvé.
  static AuthState of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<AuthProvider>();
    if (provider == null) {
      throw FlutterError(
        'AuthProvider.of() called with a context that does not contain an AuthProvider.\n'
        'Ensure that your widget tree includes AuthProvider above this context.',
      );
    }
    return provider.notifier!;
  }

  /// Accès facultatif à AuthState. Retourne null si non trouvé.
  static AuthState? maybeOf(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<AuthProvider>();
    return provider?.notifier;
  }
}
