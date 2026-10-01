import 'dart:convert';

import 'package:api_dashboard/data/api_client.dart';
import 'package:api_dashboard/notifications/system_notifier.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A system notifier that records what it was asked to show.
class FakeNotifier implements SystemNotifier {
  FakeNotifier({
    this.current = NotifPermission.undecided,
    this.onRequest = NotifPermission.granted,
  });

  NotifPermission current;

  /// What a permission prompt will answer.
  NotifPermission onRequest;
  int requests = 0;
  final shown = <({int id, String title, String body})>[];

  @override
  bool get supported => current != NotifPermission.unsupported;

  @override
  Future<NotifPermission> permission() async => current;

  @override
  Future<NotifPermission> requestPermission() async {
    requests++;
    current = onRequest;
    return current;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    shown.add((id: id, title: title, body: body));
  }
}

Map<String, dynamic> eventJson(
  int id, {
  String provider = 'stripe',
  String? displayName,
  String type = 'uptime',
  String kind = 'opened',
  String message = 'uptime 50.00% is below 99.9%',
  int? durationSeconds,
  DateTime? at,
}) => {
  'id': id,
  'provider': provider,
  'displayName': displayName,
  'type': type,
  'kind': kind,
  'message': message,
  'timestamp': (at ?? DateTime.utc(2026, 1, 1, 12)).toIso8601String(),
  'durationSeconds': durationSeconds,
};

/// A backend that serves `/api/events` like the real one: the most recent
/// `limit` events with an id above `after`, oldest first.
class FakeEventsBackend {
  final events = <Map<String, dynamic>>[];
  final requests = <Uri>[];

  /// Status to answer with instead of events (401 to test auth).
  int? failWith;
  bool offline = false;

  void add(Map<String, dynamic> event) => events.add(event);

  Future<http.Response> handle(http.Request req) async {
    requests.add(req.url);
    if (offline) throw http.ClientException('offline');
    if (failWith != null) return http.Response('{}', failWith!);
    if (req.url.path != '/api/events') return http.Response('{}', 404);
    final after = int.tryParse(req.url.queryParameters['after'] ?? '') ?? 0;
    final limit = int.tryParse(req.url.queryParameters['limit'] ?? '') ?? 50;
    final matching = events.where((e) => (e['id'] as int) > after).toList();
    final page = matching.length > limit
        ? matching.sublist(matching.length - limit)
        : matching;
    return http.Response(jsonEncode({'events': page}), 200);
  }

  ApiClient client({String? token}) => ApiClient(
    baseUrl: 'http://api.test',
    apiToken: token,
    client: MockClient(handle),
  );
}
