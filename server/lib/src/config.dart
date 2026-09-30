import 'dart:convert';
import 'dart:io';

/// Resolves the Stripe secret key: the `STRIPE_API_KEY` environment variable
/// wins, otherwise `STRIPE_SECRET_KEY` from the JSON file at [configPath].
/// Returns null when neither is available.
String? readStripeKey(Map<String, String> env, {String? configPath}) {
  final fromEnv = env['STRIPE_API_KEY'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

  final file = File(configPath ?? env['CONFIG_PATH'] ?? '../config.json');
  if (!file.existsSync()) return null;
  final json = jsonDecode(file.readAsStringSync());
  final key = json is Map ? json['STRIPE_SECRET_KEY'] : null;
  return key is String && key.isNotEmpty ? key : null;
}
