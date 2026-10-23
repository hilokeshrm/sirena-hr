import 'package:flutter/material.dart';

import 'core/session.dart';
import 'core/theme.dart';
import 'router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
