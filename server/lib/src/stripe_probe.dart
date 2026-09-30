import 'http_probe.dart';

/// Probes Stripe by calling the authenticated, read-only `GET /v1/balance`.
///
/// Use a test-mode secret key (`sk_test_...`). Retry behaviour and error
/// categories come from [HttpProbe].
class StripeProbe extends HttpProbe {
  StripeProbe({
    required String apiKey,
    String name = providerName,
    super.client,
    super.now,
    super.stopwatch,
    super.timeout,
    super.retries,
    Uri? endpoint,
  }) : super(
         provider: name,
         endpoint: endpoint ?? Uri.parse('https://api.stripe.com/v1/balance'),
         headers: {'Authorization': 'Bearer $apiKey'},
       );

  static const providerName = 'stripe';
}
