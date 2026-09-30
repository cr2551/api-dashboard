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
| README describing what it does, architecture and setup | ✅ | [README.md](README.md). The explicit pipeline diagram and design rationale are tracked in [#33](https://github.com/cr2551/api-dashboard/issues/33) |
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
| Basic query layer (last N results per service) | 🟡 | Only a time-window query exists. Missing "last N": [#35](https://github.com/cr2551/api-dashboard/issues/35) |

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
| Define SLA thresholds (p95 latency, uptime %) | ✅ | `SlaPolicy`; hardcoded defaults until [#26](https://github.com/cr2551/api-dashboard/issues/26)/[#29](https://github.com/cr2551/api-dashboard/issues/29) |
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
| Test full pipeline with a deliberate false breach | ✅ | `test/pipeline_test.dart` (probe to ntfy, faked network) and `dart run bin/drill.dart`. Drill run 2026-09-30 against a local fake endpoint: 1 alert when it broke, silence while it stayed down, 1 recovery after 7s. Console only; the live ntfy push still needs a run with `NTFY_TOPIC` set: [#25](https://github.com/cr2551/api-dashboard/issues/25) |

## Phase 6: Expand coverage

| Task | Status | Issue |
|---|---|---|
| Add second and third API | ⬜ | [#27](https://github.com/cr2551/api-dashboard/issues/27) |
| Make thresholds configurable per service | ⬜ | [#29](https://github.com/cr2551/api-dashboard/issues/29) |
| Config file (YAML/JSON) for services | 🟡 | Schema, validating loader and `services.example.json` done ([#26](https://github.com/cr2551/api-dashboard/issues/26)); `serve.dart` does not read it yet: [#28](https://github.com/cr2551/api-dashboard/issues/28) |

## Phase 7: Flutter dashboard

| Task | Status | Issue |
|---|---|---|
| Status screen showing current status per service | ✅ | [#14](https://github.com/cr2551/api-dashboard/issues/14) |
| Uptime % and latency trend chart | ✅ | [#15](https://github.com/cr2551/api-dashboard/issues/15) |
| Connect Flutter app to backend API | ✅ | [#11](https://github.com/cr2551/api-dashboard/issues/11), [#12](https://github.com/cr2551/api-dashboard/issues/12), [#13](https://github.com/cr2551/api-dashboard/issues/13) |
| Basic auth if backend is exposed publicly | ⬜ | Backend: [#30](https://github.com/cr2551/api-dashboard/issues/30), app: [#31](https://github.com/cr2551/api-dashboard/issues/31) |
| Deploy backend somewhere persistent | ⬜ | [#32](https://github.com/cr2551/api-dashboard/issues/32) |

## Phase 8: Documentation

| Task | Status | Issue |
|---|---|---|
| Document architecture and SLA/debounce design decisions | 🟡 | README has a component overview; pipeline diagram and rationale missing: [#33](https://github.com/cr2551/api-dashboard/issues/33) |
| Document real breaches as case studies | ⬜ | [#34](https://github.com/cr2551/api-dashboard/issues/34) |

## Who can work on what

### Independent now (no other open task needed)

| Component | Issues |
|---|---|
| backend / storage | [#35](https://github.com/cr2551/api-dashboard/issues/35) last-N query |
| backend / scheduling | [#17](https://github.com/cr2551/api-dashboard/issues/17) logging |
| backend / alerting | [#24](https://github.com/cr2551/api-dashboard/issues/24) recovery notification |
| backend / coverage | [#27](https://github.com/cr2551/api-dashboard/issues/27) more API probes |
| backend / security | [#30](https://github.com/cr2551/api-dashboard/issues/30) API auth |

Tasks in the same area can touch the same files (for example anything that changes `Monitor`), so tell each other before starting.

### Blocked until others are done

| Issue | Waits for |
|---|---|
| [#25](https://github.com/cr2551/api-dashboard/issues/25) full pipeline test | #24 |
| [#28](https://github.com/cr2551/api-dashboard/issues/28) multi-service serve.dart | #26 (done), #27 to be useful |
| [#29](https://github.com/cr2551/api-dashboard/issues/29) per-service thresholds | #26 |
| [#31](https://github.com/cr2551/api-dashboard/issues/31) app credentials | #30 |
| [#32](https://github.com/cr2551/api-dashboard/issues/32) deploy | #30 |
| [#34](https://github.com/cr2551/api-dashboard/issues/34) case studies | #32 (and a real breach to write about) |

### Dependency chains

```
#21 channel ──> #22 send ──┬──> #23 wire ──┐
#20 tracker ───────────────┤               ├──> #25 pipeline test
                           └──> #24 recovery┘
#26 config ──┬──> #28 multi-service
             └──> #29 per-service thresholds
#30 api auth ──┬──> #31 app credentials
               └──> #32 deploy ──> #34 case studies (also needs #23)
#19 debounce + #20 tracker ──> #33 design docs
```

## Earlier completed work

- [PR #3](https://github.com/cr2551/api-dashboard/pull/3): project description, CLAUDE.md, CI workflow.
- [PR #10](https://github.com/cr2551/api-dashboard/pull/10): Dart backend (Stripe probe, SQLite, SLA detection, alerting, CLI).
- [PR #16](https://github.com/cr2551/api-dashboard/pull/16): dashboard (JSON API, status screen, latency chart).
