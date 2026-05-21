import 'package:flutter/services.dart';

class AppEnv {
  static final Map<String, String> _values = <String, String>{};
  static bool _loaded = false;

  static Future<void> load({String assetPath = '.env'}) async {
    if (_loaded) return;

    try {
      final raw = await rootBundle.loadString(assetPath);
      for (final line in raw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

        final separatorIndex = trimmed.contains('=')
            ? trimmed.indexOf('=')
            : trimmed.indexOf(':');
        if (separatorIndex <= 0) continue;

        final key = trimmed.substring(0, separatorIndex).trim();
        final value = trimmed.substring(separatorIndex + 1).trim();
        if (key.isNotEmpty) {
          _values[key] = value;
        }
      }
    } catch (_) {
      // Ignore missing env file and let the caller handle unavailable values.
    } finally {
      _loaded = true;
    }
  }

  static String? get(String key) => _values[key];
}
