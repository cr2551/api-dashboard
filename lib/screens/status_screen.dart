import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/service_event.dart';
import '../notifications/notification_center.dart';
import '../widgets/notification_bell.dart';
import '../widgets/service_card.dart';
import '../widgets/token_dialog.dart';
import 'notifications_screen.dart';
import 'service_detail_screen.dart';

/// Home screen: current status of every monitored service.
class StatusScreen extends StatefulWidget {
  const StatusScreen({
    super.key,
    required this.client,
    this.refreshInterval = const Duration(seconds: 10),
    this.onOpenService,
    this.notifications,
  });

  final ApiClient client;

  /// Alerts feed and system notifications. The bell and in-app alert
  /// snackbars only appear when this is provided.
  final NotificationCenter? notifications;

  /// How often to poll the backend; null disables auto-refresh.
  final Duration? refreshInterval;

  /// Overrides the default navigation to the service detail screen.
  final void Function(ServiceStatus service)? onOpenService;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  StatusSnapshot? _snapshot;
  String? _error;
  bool _loading = true;
  bool _unauthorized = false;
  bool _tokenRejected = false;
  Timer? _timer;
  StreamSubscription<List<ServiceEvent>>? _alerts;

  @override
  void initState() {
    super.initState();
    _alerts = widget.notifications?.newEvents.listen(_showAlertSnackBar);
    _refresh();
    final interval = widget.refreshInterval;
    if (interval != null) {
      // Polling with a missing or wrong token would only repeat the 401.
      _timer = Timer.periodic(interval, (_) {
        if (!_unauthorized) _refresh();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _alerts?.cancel();
    super.dispose();
  }

  /// Tells the user about a new alert inside the app, which needs no
  /// notification permission.
  void _showAlertSnackBar(List<ServiceEvent> events) {
    if (!mounted) return;
    // Another screen on top (the alerts list or a service) already shows or
    // is about to show these, so a snackbar would only be noise.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final latest = events.last;
    final text = events.length == 1
        ? '${latest.title}: ${latest.body}'
        : '${events.length} new alerts, latest: ${latest.title}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: SnackBarAction(label: 'View', onPressed: _openNotifications),
        ),
      );
  }

  void _openNotifications() {
    final center = widget.notifications;
    if (center == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(
          center: center,
          onOpenService: (e) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ServiceDetailScreen(
                client: widget.client,
                provider: e.provider,
                displayName: e.displayName,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    try {
      final snapshot = await widget.client.getStatus();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _unauthorized = false;
        _loading = false;
      });
    } on UnauthorizedException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _unauthorized = true;
        _tokenRejected = e.hadToken;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _unauthorized = false;
        _loading = false;
      });
    }
  }

  Future<void> _enterToken() async {
    final token = await showTokenDialog(context, rejected: _tokenRejected);
    if (token == null || !mounted) return;
    widget.client.apiToken = token;
    widget.notifications?.resume();
    await _refresh();
  }

  void _openDetail(ServiceStatus service) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServiceDetailScreen(
          client: widget.client,
          provider: service.provider,
          displayName: service.displayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Dashboard'),
        actions: [
          if (widget.notifications != null)
            NotificationBell(
              center: widget.notifications!,
              onPressed: _openNotifications,
            ),
          IconButton(
            tooltip: 'Access token',
            icon: const Icon(Icons.key),
            onPressed: _enterToken,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _ErrorView(
        message: _error!,
        onRetry: _refresh,
        onEnterToken: _unauthorized ? _enterToken : null,
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              MaterialBanner(
                content: Text('Showing last known data. $_error'),
                leading: const Icon(Icons.cloud_off),
                actions: [
                  if (_unauthorized)
                    TextButton(
                      onPressed: _enterToken,
                      child: const Text('Enter access token'),
                    ),
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            for (final service in snapshot.services)
              ServiceCard(
                service: service,
                now: snapshot.generatedAt,
                onTap: () => (widget.onOpenService ?? _openDetail)(service),
              ),
            if (snapshot.services.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No services are being monitored.')),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    this.onEnterToken,
  });

  final String message;
  final VoidCallback onRetry;

  /// Set when the error is a 401, so the user can fix it right here.
  final VoidCallback? onEnterToken;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (onEnterToken != null) ...[
              FilledButton(
                onPressed: onEnterToken,
                child: const Text('Enter access token'),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ] else
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
