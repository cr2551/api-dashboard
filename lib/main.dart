import 'package:flutter/material.dart';

import 'data/api_client.dart';
import 'screens/status_screen.dart';

void main() {
  runApp(DashboardApp(client: ApiClient()));
}

class DashboardApp extends StatelessWidget {
  const DashboardApp({super.key, required this.client});

  final ApiClient client;

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
      home: StatusScreen(client: client),
    );
  }
}
