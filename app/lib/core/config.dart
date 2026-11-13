/// Build-time settings. Override with --dart-define, e.g.
///   flutter run -d chrome --dart-define=API_BASE=https://hr.example.com/api
class AppConfig {
  /// Android emulator: use http://10.0.2.2:3000/api to reach your PC.
  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:3000/api');

  /// SHA-256 fingerprint of the server's self-signed certificate (hex, colons optional).
  /// When set, phones trust exactly that certificate; leave empty for a normal CA-signed one.
  static const serverCertSha256 = String.fromEnvironment('SERVER_CERT_SHA256');

  /// Who to write to when something is wrong with the app itself.
  static const supportEmail = 'dev@sirenatech.com';

  /// Server origin without the /api suffix (used for download links).
  static String get origin => apiBase.endsWith('/api') ? apiBase.substring(0, apiBase.length - 4) : apiBase;
}
