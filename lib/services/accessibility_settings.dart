import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FontSizeOption { small, medium, large, extraLarge }

extension FontSizeOptionData on FontSizeOption {
  double get scale {
    switch (this) {
      case FontSizeOption.small:
        return 0.85;
      case FontSizeOption.medium:
        return 1.0;
      case FontSizeOption.large:
        return 1.25;
      case FontSizeOption.extraLarge:
        return 1.6;
    }
  }

  String get label {
    switch (this) {
      case FontSizeOption.small:
        return 'Small';
      case FontSizeOption.medium:
        return 'Medium';
      case FontSizeOption.large:
        return 'Large';
      case FontSizeOption.extraLarge:
        return 'Extra Large';
    }
  }
}

const _fontSizeOptionKey = 'accessibility_font_size_option';
const _highContrastKey = 'accessibility_high_contrast';

/// App-wide accessibility settings (font scale + high contrast), persisted
/// locally and applied at the MaterialApp root so they affect every screen.
class AccessibilitySettings extends ChangeNotifier {
  AccessibilitySettings._();

  static final AccessibilitySettings instance = AccessibilitySettings._();

  FontSizeOption fontSizeOption = FontSizeOption.medium;
  bool highContrastEnabled = false;

  double get fontScale => fontSizeOption.scale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedOption = prefs.getString(_fontSizeOptionKey);
    if (storedOption != null) {
      fontSizeOption = FontSizeOption.values.firstWhere(
        (option) => option.name == storedOption,
        orElse: () => FontSizeOption.medium,
      );
    }
    highContrastEnabled = prefs.getBool(_highContrastKey) ?? false;
    notifyListeners();
  }

  Future<void> setFontSizeOption(FontSizeOption option) async {
    fontSizeOption = option;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontSizeOptionKey, option.name);
  }

  Future<void> setHighContrast(bool enabled) async {
    highContrastEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_highContrastKey, enabled);
  }

  Future<void> reset() async {
    fontSizeOption = FontSizeOption.medium;
    highContrastEnabled = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontSizeOptionKey, fontSizeOption.name);
    await prefs.setBool(_highContrastKey, highContrastEnabled);
  }
}
