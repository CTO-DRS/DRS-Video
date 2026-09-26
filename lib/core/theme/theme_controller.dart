import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../utils/logger.dart';

enum ThemeModeSetting { system, light, dark }

enum LayoutSetting { compact, comfortable }

enum LanguageSetting { system, arabic, english }

/// Persists and exposes UI appearance settings.
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs) {
    _mode = ThemeModeSetting.values.firstWhere(
      (m) => m.name == _prefs.getString(PrefKeys.themeMode),
      orElse: () => ThemeModeSetting.system,
    );
    _dynamicColor = _prefs.getBool(PrefKeys.dynamicColor) ?? true;
    _animations = _prefs.getBool(PrefKeys.animationsEnabled) ?? true;
    _layout = LayoutSetting.values.firstWhere(
      (l) => l.name == _prefs.getString(PrefKeys.layoutMode),
      orElse: () => LayoutSetting.comfortable,
    );
    _language = LanguageSetting.values.firstWhere(
      (l) => l.name == _prefs.getString(PrefKeys.languageCode),
      orElse: () => LanguageSetting.system,
    );
  }

  final SharedPreferences _prefs;
  late ThemeModeSetting _mode;
  late bool _dynamicColor;
  late bool _animations;
  late LayoutSetting _layout;
  late LanguageSetting _language;

  ThemeModeSetting get mode => _mode;
  bool get dynamicColor => _dynamicColor;
  bool get animations => _animations;
  LayoutSetting get layout => _layout;
  LanguageSetting get language => _language;

  ThemeMode get materialMode => switch (_mode) {
        ThemeModeSetting.system => ThemeMode.system,
        ThemeModeSetting.light => ThemeMode.light,
        ThemeModeSetting.dark => ThemeMode.dark,
      };

  Locale? get localeOverride => switch (_language) {
        LanguageSetting.system => null,
        LanguageSetting.arabic => const Locale('ar'),
        LanguageSetting.english => const Locale('en'),
      };

  void _set(String key, Object value) {
    if (value is bool) _prefs.setBool(key, value);
    if (value is String) _prefs.setString(key, value);
    notifyListeners();
  }

  void setMode(ThemeModeSetting m) {
    _mode = m;
    _set(PrefKeys.themeMode, m.name);
  }

  void setDynamicColor(bool v) {
    _dynamicColor = v;
    _set(PrefKeys.dynamicColor, v);
  }

  void setAnimations(bool v) {
    _animations = v;
    _set(PrefKeys.animationsEnabled, v);
    AppLogger.instance.info('theme', 'animations=$v');
  }

  void setLayout(LayoutSetting l) {
    _layout = l;
    _set(PrefKeys.layoutMode, l.name);
  }

  void setLanguage(LanguageSetting l) {
    _language = l;
    _set(PrefKeys.languageCode, l.name);
  }
}
