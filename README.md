# API Dashboard

A SaaS Status & SLA Breach Monitor. It actively probes external APIs from our own system (starting with payment processors like Stripe), measures latency and uptime, and alerts when a provider breaches a defined SLA threshold.

## Architecture

- **Frontend:** Flutter (this repo's `lib/`), a dashboard for provider status, latency/uptime history, SLA definitions and alerts.
- **Backend:** owns the core logic:
  - **Probing:** scheduled active requests to external APIs.
  - **Storage:** persisting probe results (latency, status, timestamps).
  - **SLA detection:** evaluating results against configured SLA thresholds.
  - **Alerting:** notifying when an SLA is breached.

  The backend is written in Dart (`server/`), stores probe results in SQLite, and starts with a Stripe probe (`GET /v1/balance` with a test-mode key). Run it with `STRIPE_API_KEY=sk_test_... dart run bin/monitor.dart` from `server/` (optional: `PROBE_INTERVAL_SECONDS`, `DB_PATH`).

## Quality

- **Automated builds and unit tests:** GitHub Actions ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs `flutter pub get`, `flutter analyze`, `flutter test` and a build on every push and pull request.

## Development

```bash
flutter pub get
flutter run
flutter test
```

## Running the dashboard

1. Start the backend (probes Stripe and serves the API on http://localhost:8080). The key is read from `STRIPE_API_KEY` or `STRIPE_SECRET_KEY` in a git-ignored `config.json` at the repo root (use a test-mode key):

   ```bash
   cd server
   dart run bin/serve.dart
   ```

2. In another terminal, start the Flutter app (Chrome, Windows, etc.):

   ```bash
   flutter run -d chrome
   ```

   Point the app at a different backend with `--dart-define=API_BASE_URL=http://host:port`.

The backend also accepts `PORT`, `PROBE_INTERVAL_SECONDS` (default 30) and `DB_PATH` (default `probes.db`).
## Probe failures and retries

Each failed probe is stored with an error category: `timeout`, `connection` (DNS, refused or dropped connection), `tls`, `http4xx`, `http5xx` or `other`.

A probe that fails at the transport level (timeout, connection or TLS) is retried once before it counts, so a single dropped packet does not hurt uptime. HTTP responses are never retried: a 4xx/5xx is a real answer from the provider. The stored latency is that of the last attempt.
