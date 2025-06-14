import 'package:flutter/material.dart';

enum CustomThemeMode { system, light, dark, amoled }

class ThemeProvider with ChangeNotifier {
  CustomThemeMode _themeMode = CustomThemeMode.system;
  MaterialColor _primarySwatch = Colors.blue;

  CustomThemeMode get themeMode => _themeMode;
  MaterialColor get primarySwatch => _primarySwatch;
  bool get isDarkMode => _themeMode == CustomThemeMode.dark || _themeMode == CustomThemeMode.amoled;

  void setThemeMode(CustomThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void setPrimarySwatch(MaterialColor color) {
    _primarySwatch = color;
    notifyListeners();
  }

  void toggleTheme() {
    switch (_themeMode) {
      case CustomThemeMode.light:
        _themeMode = CustomThemeMode.dark;
        break;
      case CustomThemeMode.dark:
        _themeMode = CustomThemeMode.light;
        break;
      case CustomThemeMode.system:
        _themeMode = CustomThemeMode.dark;
        break;
      case CustomThemeMode.amoled:
        _themeMode = CustomThemeMode.light;
        break;
    }
    notifyListeners();
  }
}