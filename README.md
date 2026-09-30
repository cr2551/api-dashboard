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

## Pipeline

Every probe interval the backend runs one cycle (`Monitor.runOnce`):

```
  probe ──> store ──> SLA check ──> debounce ──> de-duplicate ──> alert
    │         │            │            │              │            │
StripeProbe ProbeStore detectBreaches consecutive-  BreachTracker  console
 (latency,  (SQLite,   over a rolling  Failures     (opened /      + ntfy.sh
  status,   one row    window: p95 +   (evaluations  resolved)     (breach and
  error     per probe) uptime %        in a row)                   recovery)
  kind)         │
                └──> JSON API (apiHandler, optional bearer token) ──> Flutter dashboard
```

1. **Probe** ([stripe_probe.dart](server/lib/src/stripe_probe.dart)): one authenticated, read-only request. Records latency, status code and an error category. Transport failures are retried once (see [Probe failures and retries](#probe-failures-and-retries)).
2. **Store** ([probe_store.dart](server/lib/src/probe_store.dart)): every result, success or failure, is one SQLite row.
3. **SLA check** ([sla.dart](server/lib/src/sla.dart)): loads the probes inside the policy window and compares p95 latency and uptime % with the thresholds.
4. **Debounce**: a breach only counts once it has held for `consecutiveFailures` evaluations in a row.
5. **De-duplicate** ([breach_tracker.dart](server/lib/src/breach_tracker.dart)): turns "what is breached right now" into events: *opened*, *resolved*, or nothing.
6. **Alert** ([alerter.dart](server/lib/src/alerter.dart), [ntfy_alerter.dart](server/lib/src/ntfy_alerter.dart)): one message when a breach opens, one when it resolves (with how long it lasted).
7. **Dashboard**: the Flutter app polls the JSON API, which reads the same SQLite rows.

Probing, SLA logic and alerting live in the backend and are plain Dart classes with injected clocks and HTTP clients, so each step is unit tested without a network; `test/pipeline_test.dart` runs them all together.

## Design decisions

### SLA is judged over a rolling window
A policy (`SlaPolicy`) is evaluated over the last `window` of probes (default 60 minutes), not over all time and not over a single probe. One probe is too noisy to judge; all-time numbers hide a problem that is happening now.

- *Trade-off:* a breach only resolves once the bad probes age out of the window, so recovery is reported up to one window late. A shorter window recovers faster but reacts more to blips.
- `minSamples` stops the SLA being judged on too little data (for example right after a restart, when there is one probe).

### p95 latency, not the average
Latency is judged by the **95th percentile** (nearest-rank), because an average hides slow tails: 95 fast requests and 5 that take 10 seconds still average out to something that looks fine, yet 1 in 20 users is waiting 10 seconds. p95 is also not dominated by a single freak outlier the way a maximum is. The average is still shown on the dashboard for context.

- Latency statistics use **successful probes only**. A failed probe (timeout, 503) has no meaningful latency, and it is already counted against uptime, so it is not punished twice.

### Uptime is the share of probes that succeeded
`uptime % = successful probes / all probes` in the window. Probes run at a fixed interval, so each one represents the same amount of time. A probe succeeds on any 2xx; 4xx and 5xx are failures (a 4xx usually means our own key is wrong, which is also worth knowing).

### Debounce: require the breach to hold
`consecutiveFailures` (default 1, meaning off) makes a breach count only after it has been true for N evaluations in a row, one evaluation per probe. It is implemented by re-judging the window as it stood after each of the previous N probes, which keeps `detectBreaches` a pure function with no stored state.

What it does and does not do:
- It filters breaches that are **not sustained**, such as a p95 latency spike that the next probe brings back down, and it resets the moment one evaluation is healthy.
- For **uptime over a long window** one failed probe keeps the window below the threshold until it ages out, so N mostly delays the alert by N-1 probes rather than hiding the blip. The real blip filters for uptime are the **retry-once** at probe level (a dropped packet never becomes a failed probe) and a realistic `minUptimePercent`. With the 99.9% default and a 60-minute window, a single failed probe out of 120 is already a breach; use `minSamples` and `consecutiveFailures` in [services.json](services.example.json) to tune this.

### One alert per incident, not one per probe
Without state, a 2-hour outage probed every 30 seconds would send 240 alerts. `BreachTracker` remembers which breaches are open, per provider and breach type (latency and uptime are tracked separately), and reports only the transitions:

| Before | Now | Event |
|---|---|---|
| not breached | breached | **opened**: alert |
| breached | breached | nothing |
| breached | not breached | **resolved**: recovery message with the duration |

- *Trade-off:* the state is **in memory**. After a restart a breach that is still active is alerted again, and its duration starts from the restart. Persisting it is a possible follow-up.

### Alerting must never stop monitoring
Storage, evaluation and alert-sending errors are logged and the cycle carries on. A broken notification channel (for example ntfy being down) cannot stop probing or the dashboard.

### Known limitations
- **Without a `services.json`** the server monitors Stripe only, with the **default policy** (60 minutes, p95 under 1 s, 99.9% uptime, no debounce), which is twitchy: one failed probe in ~120 already breaches. Copy [services.example.json](services.example.json) to `services.json` to tune thresholds per service.
- Probes are plain `GET`s judged by status code. There is no request body, POST, or response-content check yet, and only Stripe has authentication built in.
- Breach state is not persisted across restarts (see above).

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

   If the backend has `API_TOKEN` set, the app shows an **Enter access token** button on the 401 error (and a key icon in the app bar to change it later). For development you can instead pass `--dart-define=API_TOKEN=<token>`. The token is kept in memory only, so the app asks again after a restart.

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

## Logging

Both `bin/serve.dart` and `bin/monitor.dart` write timestamped lines (`2026-01-01T12:00:00.000Z INFO  stripe ok 123ms 200`) covering each probe, breaches, sent alerts and storage or alert errors. Set `LOG_LEVEL` to `debug`, `info` (default), `warn` or `error` to choose how much is shown.

## Testing the alert pipeline

- `dart test test/pipeline_test.dart` runs probe, storage, SLA, alert and recovery end to end with a fake Stripe endpoint and a fake ntfy server.
- `dart run bin/drill.dart` (from `server/`) runs the real pipeline once a second against a local fake endpoint that fails for four probes, then heals. It prints one breach alert, silence while the outage lasts, and one recovery. Set `NTFY_TOPIC` first to see real push notifications.

## Services config

[services.example.json](services.example.json) describes what to monitor. Copy it to `services.json` (next to `config.json`, at the repo root) and edit it, or point `SERVICES_CONFIG` at another path. `serve.dart` and `monitor.dart` run **one monitor per service**, each with its own interval, timeout and SLA thresholds, and `/api/status` lists all of them. **The file never contains secrets**: API keys stay in env vars or the git-ignored `config.json`.

```json
{
  "services": [
    {
      "name": "stripe",
      "type": "stripe",
      "intervalSeconds": 30,
      "sla": { "maxP95LatencyMs": 1000, "minUptimePercent": 99.9, "consecutiveFailures": 2 }
    },
    {
      "name": "github",
      "type": "http",
      "endpoint": "https://api.github.com/rate_limit",
      "intervalSeconds": 60,
      "sla": { "minUptimePercent": 99, "minSamples": 5 }
    }
  ]
}
```

Without a services file (and without `SERVICES_CONFIG`) the server falls back to Stripe only with default thresholds, as before. A `SERVICES_CONFIG` that points at a missing file, or an invalid file, stops the server at startup with a message naming the problem.

### Probe types

| `type` | What it does | Needs |
|---|---|---|
| `stripe` | Authenticated `GET /v1/balance` (read-only). | `STRIPE_API_KEY` or `STRIPE_SECRET_KEY` in `config.json` (test-mode key) |
| `http` | Plain `GET` of `endpoint`. Success is any 2xx, or exactly `expectedStatus` when set. | `endpoint`; no key |

The example file monitors three keyless public APIs alongside Stripe, chosen because they are free, read-only and need no signup:

| Service | Endpoint | Why |
|---|---|---|
| `github` | `https://api.github.com/rate_limit` | A widely used real API. This endpoint does not use up the 60 requests/hour unauthenticated quota. |
| `frankfurter` | `https://api.frankfurter.dev/v1/latest` | Free exchange-rate API, finance-flavoured like Stripe. (The old `api.frankfurter.app` now redirects here.) |
| `httpbin` | `https://httpbin.org/status/200` | A public test server. Change the path to `/status/503` or `/delay/5` to provoke a breach on purpose. It is sometimes flaky, so it has relaxed thresholds. |

These are third-party sites: keep intervals at 60 s or more to be polite, and expect the occasional false breach that is their outage, not yours.

### Fields

| Field | Required | Default | Meaning |
|---|---|---|---|
| `name` | yes | | Unique service name, used in the API, alerts and logs. |
| `type` | yes | | Probe type: `stripe` or `http`. |
| `endpoint` | `http`: yes | the probe's own | The probed http(s) URL. |
| `expectedStatus` | no | any 2xx | Exact status that counts as success (`http` only), 100 to 599. |
| `intervalSeconds` | no | 60 | Seconds between probes. |
| `timeoutSeconds` | no | 10 | Per-request timeout. |
| `sla.maxP95LatencyMs` | no | 1000 | p95 latency limit. |
| `sla.minUptimePercent` | no | 99.9 | Uptime floor, 0 to 100. |
| `sla.windowMinutes` | no | 60 | Rolling window the SLA is judged over. |
| `sla.minSamples` | no | 1 | Fewer probes than this in the window are not judged. |
| `sla.consecutiveFailures` | no | 1 | A breach must hold this many evaluations in a row before alerting. |

`loadServicesConfig(path)` validates the file. Unknown fields are rejected so a typo cannot silently fall back to a default, and errors name the exact field, e.g. `Invalid config at services[1].sla.minUptimePercent: must be a number between 0 and 100`.
## API authentication

Set `API_TOKEN` (env var, else the git-ignored `config.json`) and every API request must send `Authorization: Bearer <token>`; anything else gets `401 {"error":"unauthorized"}`. The CORS preflight (`OPTIONS`) stays open, since browsers send it without credentials, and 401 responses still carry CORS headers so the dashboard can read them.

```bash
API_TOKEN=$(openssl rand -hex 32) dart run bin/serve.dart
curl -H "Authorization: Bearer <token>" http://localhost:8080/api/status
```

Without `API_TOKEN` the API is open and `serve.dart` logs a warning. That is only acceptable because it listens on localhost; set a token before exposing it (see [#32](https://github.com/cr2551/api-dashboard/issues/32)), and use HTTPS, because a bearer token is readable on plain HTTP.
