import 'dart:convert';
import 'dart:io';

/// Resolves a setting: the environment variable [key] wins, otherwise the
/// same key in the JSON file at [configPath] (default `CONFIG_PATH` or
/// `../config.json`). Returns null when neither is set or both are empty.
String? readSetting(String key, Map<String, String> env, {String? configPath}) {
  final fromEnv = env[key];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

  final file = File(configPath ?? env['CONFIG_PATH'] ?? '../config.json');
  if (!file.existsSync()) return null;
  final json = jsonDecode(file.readAsStringSync());
  final value = json is Map ? json[key] : null;
  return value is String && value.isNotEmpty ? value : null;
}

/// Resolves the Stripe secret key: the `STRIPE_API_KEY` environment variable
/// wins, otherwise `STRIPE_SECRET_KEY` from the JSON file at [configPath].
/// Returns null when neither is available.
String? readStripeKey(Map<String, String> env, {String? configPath}) {
  final fromEnv = env['STRIPE_API_KEY'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  return readSetting('STRIPE_SECRET_KEY', env, configPath: configPath);
}
