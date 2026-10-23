/// Build-time settings. Override with --dart-define, e.g.
///   flutter run -d chrome --dart-define=API_BASE=https://hr.example.com/api
class AppConfig {
  /// Android emulator: use http://10.0.2.2:3000/api to reach your PC.
  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:3000/api');

  /// Server origin without the /api suffix (used for download links).
  static String get origin => apiBase.endsWith('/api') ? apiBase.substring(0, apiBase.length - 4) : apiBase;
}
