# Project progress

Single source of truth for what is built and what is left. **Update this file in the same PR that finishes a task** (change the status, add the issue/PR link).

Legend: ✅ done · 🟡 partly done · ⬜ not started

Each open task is a GitHub issue in the [Project board](https://github.com/users/cr2551/projects/2), grouped by:

- **Milestone** = the goal (Phase 1-8 below).
- **Label `component:*`** = the part of the system (`backend`, `frontend`, `infra`, `docs`).
- **Label `independent`** = can be picked up right now. **`has-dependencies`** = wait for the issues listed under "Depends on" in the issue body (also shown below).

## Repo setup

| Step | Status | Notes |
|---|---|---|
| README describing what it does, architecture and setup | ✅ | [README.md](README.md). Pipeline diagram and design rationale: [#33](https://github.com/cr2551/api-dashboard/issues/33) |
| `.gitignore` for Flutter + Dart backend | ✅ | Root `.gitignore` (also ignores `config.json`) and `server/.gitignore` (`*.db`, `.dart_tool/`) |
| GitHub Project board with phases and issues | ✅ | Project 2; phases are milestones, components are labels |

## Phase 1: Foundation: ✅ complete

| Task | Status | Notes |
|---|---|---|
| Pick first target API (Stripe test mode) | ✅ | |
| Set up API credentials (test keys) | ✅ | Key in git-ignored `config.json` or `STRIPE_API_KEY` |
| Identify a safe, read-only endpoint | ✅ | `GET /v1/balance` |
| Set up backend dev environment | ✅ | Dart package in `server/` ([#4](https://github.com/cr2551/api-dashboard/issues/4)) |
| Write basic probe (call, measure latency, capture status) | ✅ | `StripeProbe` ([#6](https://github.com/cr2551/api-dashboard/issues/6)) |

## Phase 2: Storage

| Task | Status | Issue |
|---|---|---|
| Design schema (service, timestamp, latency_ms, status_code, success, error_message) | ✅ | `probe_results` table; the column is `provider` rather than `service` |
| Set up SQLite | ✅ | [#7](https://github.com/cr2551/api-dashboard/issues/7) |
| Insert logic for each probe run | ✅ | `ProbeStore.insert` |
| Basic query layer (last N results per service) | ✅ | `query` (time window) and `latest(provider, limit)` (newest first): [#35](https://github.com/cr2551/api-dashboard/issues/35) |

## Phase 3: Scheduling

| Task | Status | Issue |
|---|---|---|
| Choose a scheduler | ✅ | Loop-based (`Timer.periodic`) |
| Probe runs automatically on an interval | ✅ | `bin/serve.dart` ([#12](https://github.com/cr2551/api-dashboard/issues/12)) |
| Logging for probe execution | ✅ | `Logger` with levels and `LOG_LEVEL`: [#17](https://github.com/cr2551/api-dashboard/issues/17) |
| Handle probe failure modes (timeouts, connection errors) | ✅ | Error categories + retry-once for transport errors: [#18](https://github.com/cr2551/api-dashboard/issues/18), [PR #39](https://github.com/cr2551/api-dashboard/pull/39) |

## Phase 4: SLA / breach detection

| Task | Status | Issue |
|---|---|---|
| Define SLA thresholds (p95 latency, uptime %) | ✅ | `SlaPolicy`; defaults when omitted, overridable per service ([#29](https://github.com/cr2551/api-dashboard/issues/29)) |
| Rolling-window calculation | ✅ | [#5](https://github.com/cr2551/api-dashboard/issues/5), [#8](https://github.com/cr2551/api-dashboard/issues/8) |
| Breach detection with debounce / consecutive-failure rule | ✅ | `SlaPolicy.consecutiveFailures` (default 1, off): [#19](https://github.com/cr2551/api-dashboard/issues/19), [PR #37](https://github.com/cr2551/api-dashboard/pull/37) |
| State tracking to avoid duplicate alerts | ✅ | `BreachTracker` (in memory): [#20](https://github.com/cr2551/api-dashboard/issues/20), [PR #37](https://github.com/cr2551/api-dashboard/pull/37) |

## Phase 5: Alerting

| Task | Status | Issue |
|---|---|---|
| Pick alert channel | ✅ | ntfy.sh, see the README: [#21](https://github.com/cr2551/api-dashboard/issues/21), [PR #38](https://github.com/cr2551/api-dashboard/pull/38) |
| Alert-sending function | ✅ | `NtfyAlerter` ([#22](https://github.com/cr2551/api-dashboard/issues/22), [PR #38](https://github.com/cr2551/api-dashboard/pull/38)) next to the console alerter ([#9](https://github.com/cr2551/api-dashboard/issues/9)) |
| Wire breach detection to alert trigger | ✅ | `Monitor` alerts only when a breach opens: [#23](https://github.com/cr2551/api-dashboard/issues/23) |
| Recovery notification | ✅ | One message per resolved breach with its duration: [#24](https://github.com/cr2551/api-dashboard/issues/24) |
| Alert says whether the service is already back | ✅ | Breach messages end with `(last probe OK)` or `(last probe failed)`; follow-up from [docs/case-studies.md](docs/case-studies.md#what-to-change). Branch `feat/alert-last-probe` |
| Recovery reports the outage, not the window | ✅ | Uptime recovery messages (console, ntfy, log) add `last failure 21:04:53 UTC` next to the breach duration; follow-up from [docs/case-studies.md](docs/case-studies.md#what-to-change). Branch `feat/recovery-last-failure` |
| Test full pipeline with a deliberate false breach | ✅ | `test/pipeline_test.dart` (probe to ntfy, faked network) and `dart run bin/drill.dart`. Drill run 2026-09-30 against a local fake endpoint: 1 alert when it broke, silence while it stayed down, 1 recovery after 7s. Console only; the live ntfy push still needs a run with `NTFY_TOPIC` set: [#25](https://github.com/cr2551/api-dashboard/issues/25) |

## Phase 6: Expand coverage

| Task | Status | Issue |
|---|---|---|
| Add second and third API | ✅ | Generic `HttpProbe` (`type: "http"`) with GitHub, Frankfurter and httpbin in the example config: [#27](https://github.com/cr2551/api-dashboard/issues/27) |
| Provider-reported status (status pages) | ✅ | New `statuspage` probe type reads a provider's public `/api/v2/status.json` (no key) and fails as `reported` ("Provider incident" chip) while an incident is declared; Square's status page is in the example config. Branch `feat/statuspage-probe` |
| Make thresholds configurable per service | ✅ | p95, uptime, window, min samples and debounce per service: [#29](https://github.com/cr2551/api-dashboard/issues/29) |
| Judge p95 only with enough samples | ✅ | `minLatencySamples` (off by default, 20 in the example config): one slow probe no longer opens a latency breach on a fresh window, as in the case-study re-run; follow-up from [docs/case-studies.md](docs/case-studies.md#what-to-change). Branch `feat/p95-min-samples` |
| Config file (YAML/JSON) for services | ✅ | Schema, validating loader, `services.example.json` ([#26](https://github.com/cr2551/api-dashboard/issues/26)); `serve.dart` and `monitor.dart` run one monitor per service ([#28](https://github.com/cr2551/api-dashboard/issues/28)) |

## Phase 7: Flutter dashboard

| Task | Status | Issue |
|---|---|---|
| Status screen showing current status per service | ✅ | [#14](https://github.com/cr2551/api-dashboard/issues/14) |
| Uptime % and latency trend chart | ✅ | [#15](https://github.com/cr2551/api-dashboard/issues/15) |
| Connect Flutter app to backend API | ✅ | [#11](https://github.com/cr2551/api-dashboard/issues/11), [#12](https://github.com/cr2551/api-dashboard/issues/12), [#13](https://github.com/cr2551/api-dashboard/issues/13) |
| Basic auth if backend is exposed publicly | ✅ | Backend bearer token (`API_TOKEN`): [#30](https://github.com/cr2551/api-dashboard/issues/30). App sends it, with a token prompt on 401: [#31](https://github.com/cr2551/api-dashboard/issues/31) |
| Degraded state on the card | ✅ | `degraded` in `/api/status` when the last probe is OK but a breach is open, shown as an amber "Degraded" chip instead of "Operational" next to the breach banner; follow-up from [docs/case-studies.md](docs/case-studies.md#what-to-change). Branch `feat/degraded-state` |
| Deploy backend somewhere persistent | ✅ | Docker Compose + Caddy (automatic HTTPS), `API_TOKEN` required (the server refuses to listen on the network without it), SQLite in a Docker volume, `restart: always` with Docker enabled at boot; steps in [deploy/README.md](deploy/README.md): [#32](https://github.com/cr2551/api-dashboard/issues/32), [PR #55](https://github.com/cr2551/api-dashboard/pull/55) |

## Phase 8: Documentation

| Task | Status | Issue |
|---|---|---|
| Document architecture and SLA/debounce design decisions | ✅ | README "Pipeline" and "Design decisions" sections: [#33](https://github.com/cr2551/api-dashboard/issues/33) |
| Document real breaches as case studies | ✅ | [docs/case-studies.md](docs/case-studies.md): a real observation run (no breach, one latency near-miss), a staged one-probe outage under the production thresholds, and the alert drill, with what to change: [#34](https://github.com/cr2551/api-dashboard/issues/34) |

## Who can work on what

### Independent now (no other open task needed)

| Component | Issues |
|---|---|
| backend | Threshold follow-ups from [docs/case-studies.md](docs/case-studies.md#what-to-change): one failed probe always opens a ~1 hour uptime breach under the example thresholds. No issue yet. |
| backend | Follow-up to [#25](https://github.com/cr2551/api-dashboard/issues/25): one live ntfy push. Run `dart run bin/drill.dart` with `NTFY_TOPIC` set and confirm the alert and the recovery arrive on a phone, then put the same topic in `deploy/.env` so the deployed monitor alerts too. |
| frontend | [#2](https://github.com/cr2551/api-dashboard/issues/2) leftover: branch `feat/dashboard-gui` has two unmerged commits (an actionable "cannot reach the backend" error in `lib/data/api_client.dart`, and step-by-step run instructions in the README). It is far behind `main`, so redo or rebase them, then close #2. |

Tasks in the same area can touch the same files (for example anything that changes `Monitor`), so tell each other before starting.

### Blocked until others are done

Nothing is blocked: every dependency of the open tasks is done.

### Dependency chains

```
#21 channel ──> #22 send ──┬──> #23 wire ──┐
#20 tracker ───────────────┤               ├──> #25 pipeline test
                           └──> #24 recovery┘
#30 api auth ──┬──> #31 app credentials
               └──> #32 deploy ──> #34 case studies (also needs #23)
```

Everything in these chains is done.

## Earlier completed work

- [PR #3](https://github.com/cr2551/api-dashboard/pull/3): project description, CLAUDE.md, CI workflow.
- [PR #10](https://github.com/cr2551/api-dashboard/pull/10): Dart backend (Stripe probe, SQLite, SLA detection, alerting, CLI).
- [PR #16](https://github.com/cr2551/api-dashboard/pull/16): dashboard (JSON API, status screen, latency chart).
