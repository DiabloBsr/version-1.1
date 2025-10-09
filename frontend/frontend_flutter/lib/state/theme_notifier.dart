import 'package:flutter/material.dart';
import '../utils/secure_storage.dart';

class ThemeNotifier extends ChangeNotifier {
  static const _storageKey = 'theme_mode';
  ThemeMode _mode;
  final bool _isPersistent;

  ThemeNotifier._(this._mode) : _isPersistent = true;

  // internal constructor used for non-persistent fallback instances
  ThemeNotifier._internal(this._mode) : _isPersistent = false;

  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  Future<void> toggle() async {
    _mode = (_mode == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    if (_isPersistent) {
      await SecureStorage.write(
          _storageKey, _mode == ThemeMode.dark ? 'dark' : 'light');
    }
  }

  static Future<ThemeNotifier> init() async {
    try {
      final val = await SecureStorage.read(_storageKey);
      final mode = val == 'dark' ? ThemeMode.dark : ThemeMode.light;
      return ThemeNotifier._(mode);
    } catch (_) {
      return ThemeNotifier._internal(ThemeMode.light);
    }
  }

  /// Non-persistent fallback instance used when ThemeProvider is absent.
  static ThemeNotifier fallback() => ThemeNotifier._internal(ThemeMode.light);

  static safeOf(BuildContext context) {}
}

/// Optional helper to access ThemeNotifier easily
class ThemeProvider extends InheritedNotifier<ThemeNotifier> {
  const ThemeProvider({
    super.key,
    required ThemeNotifier notifier,
    required Widget child,
  }) : super(notifier: notifier, child: child);

  /// Strict accessor that asserts the provider exists (keeps original behaviour)
  static ThemeNotifier of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ThemeProvider>();
    assert(provider != null, 'ThemeProvider not found in widget tree');
    return provider!.notifier!;
  }

  static ThemeNotifier safeOf(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ThemeProvider>();
    return provider?.notifier ?? ThemeNotifier.fallback();
  }
}
