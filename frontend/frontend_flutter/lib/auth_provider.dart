import 'package:flutter/widgets.dart';
import 'auth_state.dart';

/// AuthProvider implemented as InheritedNotifier so widgets depending on it
/// rebuild when AuthState.notifyListeners() is called.
class AuthProvider extends InheritedNotifier<AuthState> {
  const AuthProvider({
    required AuthState authState,
    required Widget child,
    super.key,
  }) : super(notifier: authState, child: child);

  static AuthState of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<AuthProvider>();
    if (provider == null) throw StateError('AuthProvider not found');
    return provider.notifier!;
  }
}
