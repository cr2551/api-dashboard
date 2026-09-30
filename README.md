# API Dashboard

A SaaS Status & SLA Breach Monitor. It actively probes external APIs from our own system (starting with payment processors like Stripe), measures latency and uptime, and alerts when a provider breaches a defined SLA threshold.

## Project status

See [PROGRESS.md](PROGRESS.md) for what is built, what is left, and which tasks can be worked on independently.

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
## Alert channel: ntfy.sh

**Decision:** alerts go to [ntfy.sh](https://ntfy.sh) (console output stays on too).

**Why:** no account or SDK, one HTTP POST per message, free push notifications on phone and desktop, and it can be self-hosted later by pointing `NTFY_SERVER` elsewhere. Email needs SMTP credentials and deliverability work; Pushover is paid and needs an app token.

**Config** (env var, else the same key in the git-ignored `config.json`; never commit these):


| Key | Required | Meaning |
|---|---|---|
| `NTFY_TOPIC` | yes | Topic to publish to. Topics on the public server are readable by anyone who knows the name, so use a long random one. Alerts are disabled (console only) when unset. |
| `NTFY_SERVER` | no | Server base URL, default `https://ntfy.sh`. |
| `NTFY_TOKEN` | no | Access token for protected topics, sent as a Bearer token. |


Delivery failures are logged, never thrown, so a broken channel cannot stop probing.

## Services config

[services.example.json](services.example.json) describes what to monitor. Copy it to `services.json` and edit it. **It never contains secrets**: API keys stay in env vars or the git-ignored `config.json`.

```json
{
  "services": [
    {
      "name": "stripe",
      "type": "stripe",
      "intervalSeconds": 30,
      "sla": { "maxP95LatencyMs": 1000, "minUptimePercent": 99.9, "consecutiveFailures": 2 }
    }
  ]
}
```

| Field | Required | Default | Meaning |
|---|---|---|---|
| `name` | yes | | Unique service name, used in the API, alerts and logs. |
| `type` | yes | | Probe type. Supported: `stripe`. |
| `endpoint` | no | the probe's own | Overrides the probed http(s) URL. |
| `intervalSeconds` | no | 60 | Seconds between probes. |
| `timeoutSeconds` | no | 10 | Per-request timeout. |
| `sla.maxP95LatencyMs` | no | 1000 | p95 latency limit. |
| `sla.minUptimePercent` | no | 99.9 | Uptime floor, 0 to 100. |
| `sla.windowMinutes` | no | 60 | Rolling window the SLA is judged over. |
| `sla.minSamples` | no | 1 | Fewer probes than this in the window are not judged. |
| `sla.consecutiveFailures` | no | 1 | A breach must hold this many evaluations in a row before alerting. |

`loadServicesConfig(path)` validates the file. Unknown fields are rejected so a typo cannot silently fall back to a default, and errors name the exact field, e.g. `Invalid config at services[1].sla.minUptimePercent: must be a number between 0 and 100`. `serve.dart` does not read this file yet; that is [#28](https://github.com/cr2551/api-dashboard/issues/28).
