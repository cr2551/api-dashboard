import 'package:shared_preferences/shared_preferences.dart';

/// What the notification feature remembers between runs: whether the user
/// turned system notifications on, and the last event they have been shown.
abstract class NotificationPrefs {
  Future<bool> loadEnabled();
  Future<void> saveEnabled(bool value);

  /// Id of the newest event already seen, or null on the very first run.
  Future<int?> loadLastEventId();
  Future<void> saveLastEventId(int id);
}

/// Stores the settings with `shared_preferences` (local storage on the web,
/// app preferences on Android). The API token is never stored here.
class SharedNotificationPrefs implements NotificationPrefs {
  static const _enabledKey = 'notifications.enabled';
  static const _lastIdKey = 'notifications.lastEventId';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<bool> loadEnabled() async =>
      (await _prefs).getBool(_enabledKey) ?? false;

  @override
  Future<void> saveEnabled(bool value) async =>
      (await _prefs).setBool(_enabledKey, value);

  @override
  Future<int?> loadLastEventId() async => (await _prefs).getInt(_lastIdKey);

  @override
  Future<void> saveLastEventId(int id) async =>
      (await _prefs).setInt(_lastIdKey, id);
}

/// Keeps the settings in memory only; for tests and as a fallback.
class MemoryNotificationPrefs implements NotificationPrefs {
  MemoryNotificationPrefs({this.enabled = false, this.lastEventId});

  bool enabled;
  int? lastEventId;

  @override
  Future<bool> loadEnabled() async => enabled;

  @override
  Future<void> saveEnabled(bool value) async => enabled = value;

  @override
  Future<int?> loadLastEventId() async => lastEventId;

  @override
  Future<void> saveLastEventId(int id) async => lastEventId = id;
}
