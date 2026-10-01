import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import '../data/service_event.dart';
import 'notification_prefs.dart';
import 'system_notifier.dart';

/// Keeps the list of alerts (breaches opened or resolved), counts the unread
/// ones, and shows a system notification for each new one when the user has
/// turned that on.
///
/// It polls `GET /api/events`, so notifications only appear while the app or
/// browser tab is running. The first time it runs it loads recent history
/// silently; after that, anything newer than the last event seen counts as
/// new, including alerts that happened while the app was closed.
class NotificationCenter extends ChangeNotifier {
  NotificationCenter({
    required this.client,
    required this.notifier,
    required this.prefs,
    this.interval = const Duration(seconds: 15),
    this.maxEvents = 200,
  });

  final ApiClient client;
  final SystemNotifier notifier;
  final NotificationPrefs prefs;
  final Duration interval;
  final int maxEvents;

  final _events = <ServiceEvent>[];
  final _newEvents = StreamController<List<ServiceEvent>>.broadcast();

  Timer? _timer;
  bool _polling = false;
  bool _needsToken = false;
  bool _disposed = false;
  int? _lastId;
  int _unread = 0;
  bool _wantsSystem = false;
  NotifPermission _permission = NotifPermission.undecided;

  /// Alerts, newest first.
  List<ServiceEvent> get events => List.unmodifiable(_events);

  /// Alerts that arrived since the list was last opened.
  int get unread => _unread;

  NotifPermission get permission => _permission;

  /// Whether system notifications are on: the user asked for them and the
  /// platform allows them.
  bool get systemEnabled =>
      _wantsSystem && _permission == NotifPermission.granted;

  /// Fires with the new alerts each time a poll finds some (not for the
  /// silent first load). The dashboard uses it for in-app snackbars.
  Stream<List<ServiceEvent>> get newEvents => _newEvents.stream;

  /// Loads the saved settings and the current permission.
  Future<void> init() async {
    _wantsSystem = await prefs.loadEnabled();
    _lastId = await prefs.loadLastEventId();
    _permission = await notifier.permission();
    if (_permission != NotifPermission.granted) {
      // The user may have revoked it since; the toggle cannot stay on.
      _wantsSystem = _wantsSystem && _permission == NotifPermission.undecided;
    }
    _notify();
  }

  /// Polls now and then every [interval].
  void start() {
    _timer?.cancel();
    poll();
    _timer = Timer.periodic(interval, (_) => poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Polling pauses after a 401 (a token is needed); call this once the user
  /// has entered one.
  void resume() {
    _needsToken = false;
    poll();
  }

  /// Fetches events newer than the last one seen.
  Future<void> poll() async {
    if (_polling || _needsToken || _disposed) return;
    _polling = true;
    try {
      var firstRun = _lastId == null;
      var page = await client.getEventsPage(after: _lastId, limit: 50);
      final latest = page.latestId;
      if (!firstRun && latest != null && latest < _lastId!) {
        // The backend now holds fewer events than we have seen: its database
        // was reset or this is a different backend. Our remembered position
        // is meaningless, so start over from its history without alerting.
        _events.clear();
        _unread = 0;
        _lastId = null;
        firstRun = true;
        page = await client.getEventsPage(limit: 50);
      }
      final fresh = page.events;
      if (_disposed) return;
      if (fresh.isEmpty) {
        if (firstRun) await _remember(0);
        return;
      }
      _events.insertAll(0, fresh.reversed);
      if (_events.length > maxEvents) {
        _events.removeRange(maxEvents, _events.length);
      }
      await _remember(fresh.last.id);
      if (!firstRun) {
        _unread += fresh.length;
        _newEvents.add(fresh);
        if (systemEnabled) await _showSystem(fresh);
      }
      _notify();
    } on UnauthorizedException {
      _needsToken = true;
    } on ApiException {
      // Connectivity problems are already reported by the status screen.
    } finally {
      _polling = false;
    }
  }

  /// Turns system notifications on or off. Turning them on asks for
  /// permission, so call this directly from a tap (the web requires a user
  /// gesture).
  Future<void> setSystemNotifications(bool on) async {
    if (!on) {
      _wantsSystem = false;
      await prefs.saveEnabled(false);
      _notify();
      return;
    }
    _permission = await notifier.requestPermission();
    _wantsSystem = _permission == NotifPermission.granted;
    await prefs.saveEnabled(_wantsSystem);
    _notify();
  }

  /// Shows a notification so the user can check the setup works.
  Future<void> sendTest() => notifier.show(
    id: 0,
    title: 'Test notification',
    body: 'Alerts like "SLA breach: Stripe" will look like this.',
  );

  void markAllRead() {
    if (_unread == 0) return;
    _unread = 0;
    _notify();
  }

  Future<void> _remember(int id) async {
    _lastId = id;
    await prefs.saveLastEventId(id);
  }

  Future<void> _showSystem(List<ServiceEvent> fresh) async {
    if (fresh.length == 1) {
      final e = fresh.single;
      await notifier.show(id: e.id, title: e.title, body: e.body);
      return;
    }
    final lines = fresh.reversed.take(3).map((e) => '${e.title}: ${e.body}');
    final more = fresh.length > 3 ? '\n+${fresh.length - 3} more' : '';
    await notifier.show(
      id: fresh.last.id,
      title: '${fresh.length} new alerts',
      body: lines.join('\n') + more,
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _newEvents.close();
    super.dispose();
  }
}
