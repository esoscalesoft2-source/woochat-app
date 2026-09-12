import 'dart:convert';

import 'package:flutter/services.dart';

/// Supabase connection settings.
///
/// Resolved from two sources, in priority order:
///
/// 1. `--dart-define` / `--dart-define-from-file` (compile-time). Use this for
///    CI and release builds.
/// 2. `assets/env/env.json` (runtime), so a plain `flutter run` works without
///    remembering any flags. The file is git-ignored; copy
///    `assets/env/env.example.json` and fill it in.
///
/// Nothing is hardcoded — if neither source supplies a value the app shows a
/// "Configuration missing" screen instead of connecting anywhere.
///
/// Note on secrecy: the Supabase anon key is a *public* client key, protected
/// by RLS, and it is embedded in the shipped bundle either way — a dart-define
/// compiles it into `main.dart.js` just as visibly. Never put a `service_role`
/// key here.
class Env {
  const Env._();

  static const String _envAssetPath = 'assets/env/env.json';

  static const String _definedUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _definedAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static String _url = _definedUrl;
  static String _anonKey = _definedAnonKey;

  static String get supabaseUrl => _url;
  static String get supabaseAnonKey => _anonKey;

  /// True when both required values resolved from either source.
  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;

  /// Names of the values that are still missing, for the setup screen.
  static List<String> get missingKeys => <String>[
        if (_url.isEmpty) 'SUPABASE_URL',
        if (_anonKey.isEmpty) 'SUPABASE_ANON_KEY',
      ];

  /// Where the values actually came from, shown on the setup screen.
  static String get source {
    if (!isConfigured) return 'none';
    if (_definedUrl.isNotEmpty && _definedAnonKey.isNotEmpty) {
      return 'dart-define';
    }
    return _envAssetPath;
  }

  /// Fills in anything `--dart-define` did not supply from the asset file.
  ///
  /// Safe to call when the asset is absent — the app simply stays unconfigured.
  static Future<void> load() async {
    if (isConfigured) return;

    try {
      final raw = await rootBundle.loadString(_envAssetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      if (_url.isEmpty) {
        _url = (decoded['SUPABASE_URL'] as String?)?.trim() ?? '';
      }
      if (_anonKey.isEmpty) {
        _anonKey = (decoded['SUPABASE_ANON_KEY'] as String?)?.trim() ?? '';
      }
    } catch (_) {
      // Asset missing or malformed — leave the values empty so the app shows
      // the setup screen rather than failing to start.
    }
  }
}
