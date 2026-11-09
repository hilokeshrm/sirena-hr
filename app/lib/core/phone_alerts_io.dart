import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

import 'config.dart';
import 'pinning.dart';
import 'session.dart';

const _task = 'sirena-check-notifications';
const _sinceKey = 'sirena_alerts_since';
const _storage = FlutterSecureStorage();
final _plugin = FlutterLocalNotificationsPlugin();

const _details = NotificationDetails(
  android: AndroidNotificationDetails('sirena_updates', 'Sirena HR updates',
      channelDescription: 'Leave decisions, requests to review and policies to read',
      importance: Importance.high, priority: Priority.high),
);

/// Runs in the background (app closed) every ~15 minutes, when Android allows it.
@pragma('vm:entry-point')
void sirenaAlertsDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      await _checkAndShow(background: true);
    } catch (_) {
      // No network or signed out: try again next time.
    }
    return true;
  });
}

/// Asks the server for unread notifications newer than the last one shown, and shows them on the phone.
Future<void> _checkAndShow({bool background = false}) async {
  final token = await _storage.read(key: Session.tokenKey);
  if (token == null) return;
  final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBase, connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 20)));
  configurePinning(dio);
  final res = await dio.get('/notifications', options: Options(headers: {'Authorization': 'Bearer $token'}));
  final items = (res.data as List).cast<Map>();
  final since = DateTime.tryParse(await _storage.read(key: _sinceKey) ?? '');
  final fresh = items
      .where((n) => n['readAt'] == null)
      .where((n) => since == null || DateTime.parse('${n['createdAt']}').isAfter(since))
      .toList()
    ..sort((a, b) => '${a['createdAt']}'.compareTo('${b['createdAt']}'));
  if (items.isNotEmpty) await _storage.write(key: _sinceKey, value: '${items.first['createdAt']}');
  // First run after sign-in: remember where we are instead of replaying old notifications.
  if (since == null) return;
  // In the app itself init() already set this up with the tap handler; setting it up again would drop it.
  if (background) await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  for (final n in fresh) {
    await _plugin.show('${n['id']}'.hashCode & 0x7fffffff, 'Sirena HR', '${n['title']}', _details, payload: n['link'] as String?);
  }
}

class PhoneAlerts {
  /// Set by the app: opens the screen a tapped notification points to.
  static void Function(String link)? onOpen;

  static Future<void> init() async {
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => onOpen?.call(r.payload ?? '/notifications'),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final link = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onOpen?.call(link ?? '/notifications'));
    }
    await Workmanager().initialize(sirenaAlertsDispatcher);
  }

  /// After sign-in: ask permission and start the background check.
  static Future<void> start() async {
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await Workmanager().registerPeriodicTask(
      _task,
      _task,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    // Mark the current notifications as already seen so only new ones pop up.
    await _checkAndShow().catchError((_) {});
  }

  /// On sign-out: stop checking and forget what was shown.
  static Future<void> stop() async {
    await Workmanager().cancelByUniqueName(_task);
    await _storage.delete(key: _sinceKey);
    await _plugin.cancelAll();
  }
}
