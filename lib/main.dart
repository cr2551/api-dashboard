import 'package:flutter/material.dart';

import 'data/api_client.dart';
import 'notifications/notification_center.dart';
import 'notifications/notification_prefs.dart';
import 'notifications/notifier_factory.dart';
import 'screens/status_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = ApiClient();
  final center = NotificationCenter(
    client: client,
    notifier: createSystemNotifier(),
    prefs: SharedNotificationPrefs(),
  );
  try {
    await center.init();
  } catch (_) {
    // Settings could not be read; the dashboard still works without them.
  }
  center.start();
  runApp(DashboardApp(client: client, notifications: center));
}

class DashboardApp extends StatelessWidget {
  const DashboardApp({super.key, required this.client, this.notifications});

  final ApiClient client;
  final NotificationCenter? notifications;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'API Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: StatusScreen(client: client, notifications: notifications),
    );
  }
}
