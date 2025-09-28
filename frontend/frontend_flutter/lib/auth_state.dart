import 'package:flutter/foundation.dart';

class AuthState extends ChangeNotifier {
  bool loggedIn = false;

  void setLoggedIn(bool value) {
    loggedIn = value;
    notifyListeners();
  }
}
