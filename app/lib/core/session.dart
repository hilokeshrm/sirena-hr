import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'phone_alerts.dart';

/// Who is signed in, and what the server says they may do.
class Session extends ChangeNotifier {
  Session._();
  static final instance = Session._();

  static const _storage = FlutterSecureStorage();
  /// Also read by the background notification check.
  static const tokenKey = 'sirena_token';
  static const _key = tokenKey;

  String? token;
  Map<String, dynamic>? me;
  bool ready = false;

  bool get signedIn => token != null && me != null;
  String get id => me?['id'] as String? ?? '';
  String get firstName {
    final n = (me?['preferredName'] ?? me?['fullName'] ?? '') as String;
    return n.split(' ').first;
  }

  Map<String, dynamic> get permissions => (me?['permissions'] as Map?)?.cast<String, dynamic>() ?? const {};
  bool can(String permission) => permissions[permission] == true;
  bool get mustChangePassword => me?['mustChangePassword'] == true;

  Future<void> restore() async {
    try {
      token = await _storage.read(key: _key);
      if (token != null) {
        me = asMap(await Api.instance.get('/me'));
        PhoneAlerts.start().ignore();
      }
    } catch (_) {
      token = null;
      me = null;
    }
    ready = true;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final res = asMap(await Api.instance.post('/auth/login', {'email': email.trim(), 'password': password}));
    token = res['accessToken'] as String;
    await _storage.write(key: _key, value: token);
    me = asMap(await Api.instance.get('/me'));
    notifyListeners();
    PhoneAlerts.start().ignore();
  }

  Future<void> refresh() async {
    me = asMap(await Api.instance.get('/me'));
    notifyListeners();
  }

  Future<void> logout() async {
    PhoneAlerts.stop().ignore();
    token = null;
    me = null;
    await _storage.delete(key: _key);
    notifyListeners();
  }
}
