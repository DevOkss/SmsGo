import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null) {
      _mode = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.dark,
      );
    }
  }

  Future<void> _saveMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _mode.name);
  }

  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    _saveMode();
    notifyListeners();
  }

  void setMode(ThemeMode mode) {
    _mode = mode;
    _saveMode();
    notifyListeners();
  }
}