import 'package:flutter/material.dart';

import 'core/phone_alerts.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PhoneAlerts.onOpen = _openLink;
  await PhoneAlerts.init().catchError((_) {});
  Session.instance.restore();
  runApp(const SirenaApp());
}

class SirenaApp extends StatelessWidget {
  const SirenaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sirena HR',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: appRouter,
    );
  }
}

/// Opens a tapped phone notification, waiting for sign-in to be restored when the app was closed.
void _openLink(String link) {
  final s = Session.instance;
  if (s.ready) {
    if (s.signedIn) appRouter.go(link);
    return;
  }
  void once() {
    if (!s.ready) return;
    s.removeListener(once);
    if (s.signedIn) appRouter.go(link);
  }
  s.addListener(once);
}
