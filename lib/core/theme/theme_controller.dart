import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../utils/logger.dart';

enum ThemeModeSetting { system, light, dark }

enum LayoutSetting { compact, comfortable }

enum LanguageSetting { system, arabic, english }

/// v1.1.0: fixed color palettes (Material 3 seeds) + system dynamic.
enum AppPalette {
  dynamic,
  nightBlue,
  emerald,
  purple,
  sunset,
  calmGray;

  /// M3 seed color for fixed palettes; null for [dynamic] (the system
  /// provides the scheme when dynamic color is available).
  Color? get seed => switch (this) {
        AppPalette.dynamic => null,
        AppPalette.nightBlue => const Color(0xFF2B5CB8),
        AppPalette.emerald => const Color(0xFF00875A),
        AppPalette.purple => const Color(0xFF7A4FB8),
        AppPalette.sunset => const Color(0xFFD06618),
        AppPalette.calmGray => const Color(0xFF5A6B7A),
      };

  static AppPalette fromName(String? name) => AppPalette.values
      .firstWhere((p) => p.name == name, orElse: () => AppPalette.dynamic);
}

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
    _palette = AppPalette.fromName(_prefs.getString(PrefKeys.palette));
  }

  final SharedPreferences _prefs;
  late ThemeModeSetting _mode;
  late bool _dynamicColor;
  late bool _animations;
  late LayoutSetting _layout;
  late LanguageSetting _language;
  late AppPalette _palette;

  ThemeModeSetting get mode => _mode;
  bool get dynamicColor => _dynamicColor;
  bool get animations => _animations;
  LayoutSetting get layout => _layout;
  LanguageSetting get language => _language;
  AppPalette get palette => _palette;

  /// The seed used by the MaterialApp when a fixed palette is selected.
  /// Null means "dynamic/system color is in charge".
  Color? get fixedSeed => _palette.seed;

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
    if (v) {
      // Dynamic color and fixed palettes are mutually exclusive.
      _palette = AppPalette.dynamic;
      _prefs.setString(PrefKeys.palette, AppPalette.dynamic.name);
    }
    _set(PrefKeys.dynamicColor, v);
  }

  /// Selects a fixed palette (or [AppPalette.dynamic] to restore system
  /// dynamic color). Persists both prefs consistently.
  void setPalette(AppPalette p) {
    _palette = p;
    if (p == AppPalette.dynamic) {
      _dynamicColor = true;
      _prefs.setBool(PrefKeys.dynamicColor, true);
    } else {
      _dynamicColor = false;
      _prefs.setBool(PrefKeys.dynamicColor, false);
    }
    _prefs.setString(PrefKeys.palette, p.name);
    notifyListeners();
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
