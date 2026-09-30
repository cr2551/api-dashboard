# API Dashboard

A SaaS Status & SLA Breach Monitor. It actively probes external APIs from our own system (starting with payment processors like Stripe), measures latency and uptime, and alerts when a provider breaches a defined SLA threshold.

## Running the app

The app has two parts that must both be running: the **backend** (probes Stripe, stores results, serves an API) and the **Flutter dashboard** (shows the data).

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (includes Dart)
- A Stripe **test-mode** secret key (`sk_test_...`) from the [Stripe dashboard](https://dashboard.stripe.com/test/apikeys)

### 1. Add your Stripe key

Create a `config.json` in the repo root (it is git-ignored, so it is never committed):

```json
{
  "STRIPE_SECRET_KEY": "sk_test_..."
}
```

Alternatively, set the `STRIPE_API_KEY` environment variable, which takes priority over the file.

### 2. Start the backend

In a terminal:

```bash
cd server
dart pub get
dart run bin/serve.dart
```

It probes Stripe every 30 seconds and serves the API on http://localhost:8080. Leave it running. You should see a line like `stripe ok 180ms 200` for each probe.

### 3. Start the dashboard

In a second terminal, from the repo root:

```bash
flutter pub get
flutter run -d chrome
```

You can use another device instead of `chrome` (for example `windows`); run `flutter devices` to list them. The status screen refreshes every 10 seconds, and tapping a service opens its latency chart.

### Troubleshooting

- **"Cannot reach the backend"**: the backend isn't running, or the app is pointed at the wrong address. Start it as in step 2, then press **Retry**. To use a different address, run the app with `--dart-define=API_BASE_URL=http://host:port`.
- **"No Stripe key"** when starting the backend: check that `config.json` is in the repo root with the `STRIPE_SECRET_KEY` field, or set `STRIPE_API_KEY`.
- **Service shows "No data"**: no probe has been recorded in the last hour yet. Wait for the next probe.
- **Port 8080 already in use**: start the backend with another port, for example `PORT=8081`, and run the app with a matching `API_BASE_URL`.

### Backend settings

| Variable | Default | Purpose |
|---|---|---|
| `STRIPE_API_KEY` | none | Stripe key; overrides `config.json` |
| `CONFIG_PATH` | `../config.json` | Path to the config file, relative to `server/` |
| `PORT` | `8080` | API port |
| `PROBE_INTERVAL_SECONDS` | `30` | Time between probes |
| `DB_PATH` | `probes.db` | SQLite file for probe results |

`bin/monitor.dart` is a console-only alternative that probes and prints alerts without serving the API.

## Architecture

- **Frontend:** Flutter (`lib/`), a dashboard for provider status, latency/uptime history, SLA definitions and alerts.
- **Backend:** Dart (`server/`), which owns the core logic:
  - **Probing:** scheduled active requests to external APIs (starting with Stripe's `GET /v1/balance`).
  - **Storage:** probe results (latency, status, timestamps) in SQLite.
  - **SLA detection:** evaluating results against configured SLA thresholds.
  - **Alerting:** notifying when an SLA is breached.
  - **API:** JSON endpoints (`/api/status`, `/api/history`) used by the dashboard.

## Development and tests

```bash
flutter test                   # Flutter tests (repo root)
cd server && dart test         # backend tests
```

## Quality

- **Automated builds and unit tests:** GitHub Actions ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs `flutter analyze`, `flutter test` and a web build for the app, and `dart analyze` and `dart test` for the backend, on every push and pull request.
