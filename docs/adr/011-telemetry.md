# ADR 011: Telemetry — Latency, Session Logs and Error Signals

## Status
Accepted

## Context
Pulsr needs observability for two distinct concerns:
1. **Tap-to-audible latency** across a long async chain (queue → cache → YTM resolution → plugin → decoder → playing), so regressions can be detected and attributed to a stage.
2. **Per-session audio diagnostics** (route, Bluetooth codec, negotiated format, interruptions, underruns/dropouts) for after-the-fact correlation and export.

Hard requirements: telemetry must never throw into the playback path, must work when Sentry is not configured, and must be bounded in memory/disk.

## Decision
We split telemetry into a real-time latency tracker, a persisted session log and an error logger/breadcrumb facility.

### 1. Playback latency (`lib/core/telemetry/playback_latency_tracker.dart`)
- `PlaybackStage` enumerates the ordered pipeline; `start()` opens a session, `markStage`/`markStageAt` record stages (idempotent — the earliest mark per stage wins to avoid skew). Reaching `playing` auto-finishes successfully; an unfinished session is force-finished as `superseded` when a new one starts.
- When Sentry is enabled each play is a transaction with one child span per stage (start = previous stage time, end = the stage mark), so slow stages are individually attributed. Without Sentry it falls back to `ErrorLogger` breadcrumbs and always emits one debug summary line per play.
- `PlaybackLatencyBucket` classifies totals (`preResolved <300 ms`, `warm <1 s`, `cold <3 s`, `overBudget`), and `meetsBudgetForScenario` gates a scenario against its budget.
- Time is read through an injectable `Clock` (`clock.dart`, `SystemClock`/`FakeClock`), making latency logic deterministic in tests. History is capped at 100 reports.

### 2. Audio session log (`lib/core/telemetry/audio_session_log.dart`)
- One JSON record is persisted per session as JSONL under the app documents directory; `_enforceRing` keeps only the newest `maxSessions` (25) records.
- Every public entry point runs through `_run`, which serializes on a write tail, checks the `PrefsKeys.audioSessionLogEnabled` flag (no-op when off) and swallows all failures — telemetry can never throw into playback.
- Records capture route transitions, interruption kinds (including becoming-noisy), codec, sample rate/bit depth and underrun/dropout counters; `routeTypeForInfo` maps an `AudioOutputInfo` to speaker/wired/bluetooth. `readAll` skips corrupt lines and `exportToFile` writes a portable copy.

### 3. Error logger and breadcrumbs
`ErrorLogger.log`/`addBreadcrumb` are the shared sink used by both telemetry paths and by services throughout the app, so diagnostics exist even without Sentry.

## Consequences
### Positive
- Latency is attributable per stage, with budget gating and deterministic tests via `Clock`.
- Session records are bounded on disk and fully exportable/clearable.
- Telemetry is best-effort and cannot destabilize playback; it degrades gracefully without Sentry.

### Negative / Trade-offs
- The session log writes to disk asynchronously; a process kill between finalize and flush can lose the last record.
- Sentry span creation is wrapped in try/catch, so a Sentry misconfiguration silently reduces fidelity to breadcrumbs.
