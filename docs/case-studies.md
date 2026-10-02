# Breach case studies

Incidents the monitor caught, written up so we learn what the numbers looked like, how quickly it alerted, and whether the thresholds are right ([#34](https://github.com/cr2551/api-dashboard/issues/34)).

Each case study answers three questions:

1. **What happened?** Which service, when, and what the probes saw (status codes, error kinds, latency).
2. **What did the monitor show?** The dashboard, the breach message, the events in `/api/events`.
3. **How quickly did it alert?** From the first bad probe to the "breach opened" event, and from the last bad probe to the recovery.

## Summary

| # | Case | Kind | Breach? | Alerted after | Recovered after |
|---|---|---|---|---|---|
| 1 | [GitHub, Frankfurter and httpbin, first observation run](#1-real-services-first-observation-run) | Real; re-run 21 min | First run: no, one near-miss. Re-run: yes, latency, all three services | Re-run: 60 s after the slow probe | Re-run: 9 to 10 min, when the window reached 20 probes |
| 2 | [One failed probe under the production thresholds](#2-one-failed-probe-under-the-production-thresholds) | Staged, real code and thresholds | Yes, uptime | 60 s (service already back up) | Not measured (both runs stopped first); expected about one window, 60 min |
| 3 | [Alert pipeline drill](#3-alert-pipeline-drill) | Drill (`bin/drill.dart`) | Yes, uptime | 5 ms | 4 s (= its window) |

All times are UTC. Cases 1 and 2 ran the backend image built from `main` at `feea54c` (the deployed version, [PR #55](https://github.com/cr2551/api-dashboard/pull/55)) with the thresholds from [services.example.json](../services.example.json); Stripe was left out because it needs a key. The dashboard was the Flutter web build of the same commit.

The first runs' start and end times and their full probe tables were not saved, so both cases were **re-run on 2026-10-01 from 20:58 to 21:20 UTC** with `dart run bin/serve.dart` on `main` at `1c98463` (no code or threshold changes since `feea54c`), the same four services and thresholds, and a fresh database. The numbers below marked "re-run" come from that run's `/api/history` and `/api/events`.

## 1. Real services, first observation run

**When:** 2026-10-01, around 16:00 (exact start and end not recorded), one probe per service per minute. Re-run: 20:58 to 21:19 (21 minutes).

**What happened:** nothing broke. Every probe of GitHub (`/rate_limit`), Frankfurter (`/v1/latest`) and httpbin (`/status/200`) returned 200, in the first run and in the re-run.

Re-run, 20:58 to 21:19:

| Service | Probes | Uptime | Median latency | Slowest probe | p95 limit |
|---|---|---|---|---|---|
| GitHub (`/rate_limit`) | 22 | 100% | 174 ms | 7183 ms at 21:06:53 | 1500 ms |
| Frankfurter (`/v1/latest`) | 22 | 100% | 107 ms | 3843 ms at 21:06:53 | 1500 ms |
| httpbin (`/status/200`) | 22 | 100% | 826 ms | 7658 ms at 21:06:53 | 3000 ms |

**The near-miss.** At 16:03:06 one GitHub probe took **1374 ms** against a 1500 ms p95 limit. At that point the window held 10 probes, and with fewer than 20 samples the nearest-rank p95 is simply the slowest probe, so the dashboard showed p95 = 1374 ms for GitHub for the next ~10 minutes. One response 126 ms slower would have opened a latency breach and sent an alert for a single slow request. Once the window held 20+ probes the spike stopped dominating (p95 at 60 probes is the 4th-slowest), which is the behaviour the SLA intends. Frankfurter had a smaller spike (560 ms at 16:04:29).

**The re-run crossed the line.** At 21:06:53 the 9th probe of all three services was slow at the same moment (GitHub 7183 ms, Frankfurter 3843 ms, httpbin 7658 ms); every other probe was normal. Three unrelated providers slowing down in the same second points to the monitoring machine's own network, not to the providers. With 9 probes in the window, p95 was that one probe, so the monitor opened **latency breaches** for GitHub and Frankfurter at 21:07:53 (`consecutiveFailures` 2) and for httpbin at 21:08:55 (`consecutiveFailures` 3), and sent three alerts. All three resolved together at 21:17:53, after 599 s, 599 s and 539 s: not when the slow probe left the 60-minute window, but when the window reached **20 probes** and nearest-rank p95 moved from the slowest probe to the second slowest.

**Takeaway:** for the first ~20 minutes of a fresh deployment (or after the history is wiped), the latency SLA is judged on the single worst probe. The first run came within 126 ms of a false alert; the re-run sent three, for one slow moment on our side. `minSamples` (5 here) protects the uptime SLA from tiny samples but is too low for p95.

## 2. One failed probe under the production thresholds

The question #34 asks is "how quickly does it alert?", and the answer depends almost entirely on the thresholds. To see it end to end without waiting for a real outage, a local fake API (`Staged blip (local test)`) was added to the same monitor with GitHub's thresholds: every 60 s, uptime ≥ 99% and p95 < 1500 ms over 60 minutes, `minSamples` 5, `consecutiveFailures` 2. It answered 200 except for exactly **one** probe, which got a 503.

| Time | Probe | What the monitor and dashboard showed |
|---|---|---|
| 16:03:28 | 1st, 200 | Service added. Card "Operational". |
| 16:08:28 | 6th, 200 | Enough samples (5) to judge the SLA. |
| 16:09:28 | **503** | Card turns **Down**, uptime 85.71% (6 of 7), "HTTP 5xx" failure chip, last probe "HTTP 503". No alert yet: the breach has held for 1 evaluation of the 2 required. |
| 16:10:28 | 200 | Service is back. Same cycle: **breach opened, alert sent** (`uptime 87.50% is below 99.0%`). Dashboard: in-app snackbar, bell badge "1", card back to "Operational" with an "SLA breach" banner under it. |
| 16:11 onward | all 200 | Breach stays open: the one failure keeps uptime below 99% (best case 59/60 = 98.33%). |
| Not recorded | 200 | Expected when the 16:09:28 failure leaves the 60-minute window: **breach resolved**, with a recovery message. Neither run was kept going that long, so the time and the duration were not measured. |

**Re-run.** The re-run reproduced every row above, one probe per minute starting at 20:58:51: six 200s, the **503** at 21:04:53 (card Down, uptime 85.71%), and at 21:05:53 a 200 together with **breach opened and alert sent** (`uptime 87.50% is below 99.0%`), exactly 60 s after the failure. At 21:20 the breach was still open with uptime 95.45% (21 of 22). The run was stopped there, before the resolution.

**What this shows:**

- **Alert delay = `(consecutiveFailures - 1) × interval`.** 60 s here, 120 s for httpbin (`consecutiveFailures` 3). The monitor itself adds milliseconds (case 3).
- **A single failed probe always breaches these thresholds.** At one probe a minute the window never holds more than 60 probes, and one failure in 60 is 98.33%, under 99%. The debounce does not help, because uptime stays low for the whole window rather than for one evaluation.
- **The alert arrived after the outage was over.** The service had recovered in the very probe that opened the breach, but the alert text (and the push it would send via ntfy) does not say so.
- **The breach outlasts the blip by far.** It was still open 15 minutes after a one-minute blip in the re-run, and should stay open for about one window (60 minutes). For an uptime breach, "recovered" means "the failure left the window", so the recovery duration measures the window, not the outage.
- **Mixed signals on the card.** While the breach was open the card said "Operational" (last probe OK) next to an "SLA breach" banner.

## 3. Alert pipeline drill

`dart run bin/drill.dart` (from `server/`) runs the real probe, store, SLA detection, breach tracker and alerter against a fake endpoint that fails probes 4 to 7, once a second, with a 4-second window and no debounce.

| Time | Event |
|---|---|
| 16:02:36.360 | First failing probe (HTTP 503) |
| 16:02:36.365 | Breach opened and alert sent: **5 ms** after the probe |
| 16:02:39.378 | Last failing probe |
| 16:02:43.404 | Breach resolved, recovery sent: 4.0 s after the last failure, exactly the window |

The pipeline adds no meaningful delay: every second between a failure and an alert or recovery comes from the policy (interval, debounce, window). The previous drill on 2026-09-30 gave the same result (see [PROGRESS.md](../PROGRESS.md), Phase 5).

## What to change

Suggested follow-ups, most useful first. None is required for the monitor to work; they make its alerts mean what a reader expects.

1. **Let one blip pass the uptime SLA.** Either lower `minUptimePercent` to 98 for one-probe-a-minute services (tolerates one failure an hour), or add a separate "down" rule (N failed probes in a row) for paging and keep the uptime SLA for reporting.
2. **Say in the alert whether the service is up right now**, for example `uptime 87.50% is below 99.0% (last probe OK)`.
3. **Report the outage, not the window, on recovery**: when the last failure happened, alongside how long the breach was open.
4. **Judge p95 only with enough samples**, for example at least 20, or a separate `minSamples` for latency.
5. **Add a "Degraded" state to the card** for "last probe OK but SLA breached".

## Collecting the next one from the deployed server

The deployed monitor ([deploy/README.md](../deploy/README.md)) keeps everything needed. On the server, from `api-dashboard/deploy`:

```bash
TOKEN=$(grep ^API_TOKEN= .env | cut -d= -f2)
DOMAIN=$(grep ^DOMAIN= .env | cut -d= -f2)
curl -s -H "Authorization: Bearer $TOKEN" "https://$DOMAIN/api/events?limit=200"
curl -s -H "Authorization: Bearer $TOKEN" "https://$DOMAIN/api/history?provider=<name>&minutes=1440"
docker compose logs --since 24h monitor | grep -E "FAIL|breach|alert|recover"
```

`/api/events` lists every breach that opened or resolved (with `durationSeconds` on recoveries), `/api/history` has the probes around it, and the log has the exact failure messages. Add a section here with the same three questions, and copy numbers, never the token.
