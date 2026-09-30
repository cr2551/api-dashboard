# CLAUDE.md

## Project

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

## Commands

- Install deps: `flutter pub get`
- Run: `flutter run`
- Analyze: `flutter analyze`
- Test: `flutter test`

## Conventions

- Every change should keep CI green (analyze + tests + build).
- Add unit tests for new logic, especially SLA detection and latency/uptime calculations.
- Keep probing/SLA logic out of widgets so it stays unit-testable.
- Backend commands run from `server/`: `dart pub get`, `dart analyze`, `dart test`.
- Run the whole app: `dart run bin/serve.dart` in `server/`, then `flutter run -d chrome` (see README).
- Flutter code: `lib/data` (models + ApiClient), `lib/screens`, `lib/widgets`. Tests mirror this under `test/`.
