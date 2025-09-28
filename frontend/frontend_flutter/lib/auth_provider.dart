import 'package:flutter/widgets.dart';
import 'auth_state.dart';

class AuthProvider extends InheritedNotifier<AuthState> {
  const AuthProvider({
    super.key,
    required AuthState notifier,
    required Widget child,
  }) : super(notifier: notifier, child: child);

  static AuthState of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<AuthProvider>();
    assert(provider != null, 'AuthProvider non trouvé dans le contexte');
    return provider!.notifier!;
  }
}