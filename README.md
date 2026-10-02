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
- Every breach message ends with whether the newest probe succeeded, for example `uptime 87.50% is below 99.0% (last probe OK)`. A breach is judged over the whole window, so the service is often already back when the alert opens; without this the alert reads like an ongoing outage.
- An uptime recovery also says when the last failed probe ran, for example `after 59m 0s, last failure 21:04:53 UTC`. An uptime breach only resolves once its failures leave the window, so the duration mostly measures the window; the last failure time is when the outage actually ended.

### Alerting must never stop monitoring
Storage, evaluation and alert-sending errors are logged and the cycle carries on. A broken notification channel (for example ntfy being down) cannot stop probing or the dashboard.

### Known limitations
- **Without a `services.json`** the server monitors Stripe only, with the **default policy** (60 minutes, p95 under 1 s, 99.9% uptime, no debounce), which is twitchy: one failed probe in ~120 already breaches. Copy [services.example.json](services.example.json) to `services.json` to tune thresholds per service.
- Probes are plain `GET`s judged by status code. There is no request body, POST, or response-content check yet, and only Stripe has authentication built in.
- Breach state is not persisted across restarts (see above).
- **With the example thresholds one failed probe opens an uptime breach** that lasts until it leaves the 60-minute window, and the alert can arrive after the service is already back. Measured in [docs/case-studies.md](docs/case-studies.md), with suggested fixes.

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

Each service card shows one of four states: **Operational** (last probe OK, no breach), **Degraded** (last probe OK, but the SLA window is still breached, for example right after a short outage), **Down** (last probe failed) or **No data** (no probes in the window).

The backend also accepts `PORT`, `HOST` (default `127.0.0.1`), `PROBE_INTERVAL_SECONDS` (default 30) and `DB_PATH` (default `probes.db`).
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
| `statuspage` | `GET` of a provider's public Atlassian Statuspage summary. Success only while it reports `status.indicator` `none`; an incident or maintenance fails as **Provider incident** with the page's own description (e.g. `major: Partial System Outage`). This catches outages the provider has declared even when its API still answers. | `endpoint`, the full `/api/v2/status.json` URL (e.g. `https://www.issquareup.com/api/v2/status.json`; GitHub, Shopify, Twilio and Discord work the same way); no key |

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
| `displayName` | no | `name` capitalised | Friendly title on the dashboard, up to 40 characters (for example `GitHub`). `name` stays the key in the API, alerts and logs. |
| `type` | yes | | Probe type: `stripe`, `http` or `statuspage`. |
| `endpoint` | `http`, `statuspage`: yes | the probe's own | The probed http(s) URL. |
| `expectedStatus` | no | any 2xx | Exact status that counts as success (`http` only), 100 to 599. |
| `intervalSeconds` | no | 60 | Seconds between probes. |
| `timeoutSeconds` | no | 10 | Per-request timeout. |
| `sla.maxP95LatencyMs` | no | 1000 | p95 latency limit. |
| `sla.minUptimePercent` | no | 99.9 | Uptime floor, 0 to 100. |
| `sla.windowMinutes` | no | 60 | Rolling window the SLA is judged over. |
| `sla.minSamples` | no | 1 | Fewer probes than this in the window are not judged. |
| `sla.minLatencySamples` | no | off | Fewer **successful** probes than this in the window: p95 latency is not judged (uptime still is). Nearest-rank p95 of fewer than 20 values is the single slowest probe, so `20` stops one slow probe from opening a latency breach; the example file uses 20. |
| `sla.consecutiveFailures` | no | 1 | A breach must hold this many evaluations in a row before alerting. |

`loadServicesConfig(path)` validates the file. Unknown fields are rejected so a typo cannot silently fall back to a default, and errors name the exact field, e.g. `Invalid config at services[1].sla.minUptimePercent: must be a number between 0 and 100`.
## Breaking things on purpose

[services.chaos.example.json](services.chaos.example.json) monitors eight endpoints that each fail in a different way, so you can see every part of the system react (dashboard states, SLA breach banners, alerts, error categories in the log). It uses public test services (`httpbin.org`, `badssl.com`, and a reserved `.invalid` hostname), so keep it running for minutes, not days.

Run it on its own port and database so it does not mix with your real history (PowerShell, from `server/`):

```powershell
$env:SERVICES_CONFIG = "../services.chaos.example.json"
$env:DB_PATH = "chaos.db"
$env:PORT = "8081"
dart run bin/serve.dart
```

then point the app at it: `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8081`.

| Service | How it fails | What to expect |
|---|---|---|
| Always 503 | `httpbin.org/status/503` | Down; uptime breach; one alert after 2 failures; error `http5xx` |
| Always 404 | `httpbin.org/status/404` | Down; error `http4xx` |
| Slow (3s) | `httpbin.org/delay/3` | Still up, but a **latency** breach (p95 over 1000 ms) |
| Times out | `/delay/5` with a 2 s timeout | Error `timeout`; probes are retried once, so each takes about 4 s |
| Flaky (1 in 3 fails) | `/status/200:2,503:1` | Uptime wobbles; debounce (3 in a row) decides whether it alerts |
| Unexpected status | `/status/204` with `expectedStatus: 200` | Fails although the server is healthy |
| DNS failure | a `.invalid` hostname | Error `connection` |
| Expired certificate | `expired.badssl.com` | Error `tls` |

The failure type is shown on each card as a chip (Timeout, Connection / DNS, TLS / certificate, HTTP 4xx, HTTP 5xx, Provider incident, Other; tap or hover for a plain-language explanation), in the detail screen as a per-type count for the selected range, and in the server log (`FAIL ... http5xx: HTTP 503`). The API exposes it as `errorKind` on each probe. Nothing in this file ever recovers, so to see a **recovery** message use `dart run bin/drill.dart` (see [Testing the alert pipeline](#testing-the-alert-pipeline)), or give a flaky service a short `windowMinutes`. Set `NTFY_TOPIC` first to get the alerts on your phone.

## Notifications in the dashboard

The server saves every breach that **opens** or **resolves** to SQLite (the `breach_events` table) and serves them at `GET /api/events?after=<id>&limit=50` (oldest first; `after` returns only newer events, `limit` is 1 to 200; protected by `API_TOKEN` like the rest of the API). The app polls it every 15 seconds and shows alerts three ways:

1. **A bell with an unread badge** in the app bar. It opens the alerts list (newest first, with the service, breach type, message, how long a breach lasted, and when). Tapping an alert opens that service.
2. **An in-app snackbar** with a *View* action when a new alert arrives and the dashboard is on screen. This needs no permission and works everywhere.
3. **System notifications** (opt-in): the **System notifications** switch at the top of the alerts list asks for permission, then shows a real pop-up for each new alert (a single summary if several arrive at once). A *Send test notification* button checks it works. The choice is remembered.

| Platform | How system notifications are shown |
|---|---|
| Browser | The browser's Notification API. The browser asks for permission when you flip the switch, and only allows it on `https://` pages or `localhost`. If you blocked it, the switch explains how to allow it again in the site settings. |
| Android | `flutter_local_notifications` on a high-importance "SLA alerts" channel. Android 13+ shows a permission prompt. |
| Windows, iOS, macOS, Linux | Not set up: the switch is disabled with an explanation, and the bell and snackbars still work. |

**What it does not do (yet):** these notifications come from the app polling, so they only appear **while the app or browser tab is running**. Nothing reaches you once it is closed or the phone has put it to sleep; for that, use the ntfy alerts above, which the server sends itself. Alerts that happened while the app was closed are listed (and counted) the next time you open it, and the first time you ever open the app the existing history loads silently instead of notifying you about old alerts. True background push (web push or Firebase) needs a deployed HTTPS backend (see [Deployment](#deployment)).

**Android:** the manifest requests `INTERNET` (needed by release builds) and `POST_NOTIFICATIONS`, and the build enables core-library desugaring, which the notification plugin requires. A release build must talk to an HTTPS backend; plain `http://` is blocked by Android. The app token and the notification settings are kept separate: the token is memory-only, while the on/off choice and the last alert seen are stored with `shared_preferences`.

## How failures are handled (in the dashboard)

Open a service and expand **How failures are handled** under the chart. It explains, with that service's real numbers, what the monitor does: how often it checks and how long it waits, whether a failed check is retried (connection, timeout and TLS failures are retried once; 4xx/5xx responses never are), what counts as a failure, the SLA it is judged against over its window, how many checks in a row a breach must hold before it alerts (the debounce), and that you get one alert when a breach opens and one when it recovers. Below that it lists the **recent alerts for that service**. The numbers come from `/api/status` (`settings` on each service); an older backend that does not send them simply shows no section.

If the backend's database is reset (or you point the app at a different backend), the app notices that the newest alert id went backwards (`latestId` in `/api/events`), drops its remembered position and reloads the history silently, so alerts are not missed.

## API authentication

Set `API_TOKEN` (env var, else the git-ignored `config.json`) and every API request must send `Authorization: Bearer <token>`; anything else gets `401 {"error":"unauthorized"}`. The CORS preflight (`OPTIONS`) stays open, since browsers send it without credentials, and 401 responses still carry CORS headers so the dashboard can read them.

```bash
API_TOKEN=$(openssl rand -hex 32) dart run bin/serve.dart
curl -H "Authorization: Bearer <token>" http://localhost:8080/api/status
```

Without `API_TOKEN` the API is open and `serve.dart` logs a warning. That is only acceptable because it listens on localhost by default. `HOST` changes the listen address (for example `0.0.0.0` in a container), and the server refuses to start on any non-loopback address without a token. Use HTTPS when it is exposed, because a bearer token is readable on plain HTTP; the deployment below does both.

## Deployment

[deploy/README.md](deploy/README.md) runs the backend on an always-on server (a free Google Cloud `e2-micro` VM, any VPS, or a Raspberry Pi) with Docker Compose: the monitor behind [Caddy](https://caddyserver.com) for automatic HTTPS, `API_TOKEN` required and kept in a git-ignored `deploy/.env`, the SQLite file in a persistent volume, and both containers restarting after a crash or a reboot. In short, on the server:

```bash
git clone https://github.com/cr2551/api-dashboard.git && cd api-dashboard
cp services.example.json deploy/services.json   # edit; drop "stripe" without a key
sh deploy/setup.sh monitor.example.com          # your domain, pointing at the server
```

then from your machine `sh deploy/check.sh monitor.example.com`, and run the app with `--dart-define=API_BASE_URL=https://monitor.example.com`.
