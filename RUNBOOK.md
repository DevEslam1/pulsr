# Pulsr Music — YouTube Music Streaming Latency Runbook

This document describes the tap-to-audible-sound latency optimization program in Pulsr Music, outlining the architectural pipeline, latency budgets, optimization breakdown, and diagnostic troubleshooting guide.

---

## 1. Latency Targets & Scenarios

| Scenario | Target Budget | Description |
|---|---|---|
| **Pre-resolved** (Next-in-queue, Replay) | **< 300 ms** | Stream URL pre-fetched in background cache; socket pre-connected. |
| **Warm** (Winning client known, poToken cached) | **< 1.0 s** | poToken loaded from disk; winner client resolved via pooled HTTP/2 connection. |
| **Cold** (Fresh install, first track, cache empty) | **2.0 – 3.0 s** | On-demand poToken generation + 350ms hedged Innertube resolution race. |

---

## 2. Tap-to-Audible Latency Architecture (8 Stages)

```
[ User Tap ]
     │
     ▼ (Stage 1: Intent Dispatch / UI event)
[ PlaybackLatencyTracker.start() ]
     │
     ├──► Check YtmUrlCache (LRU In-Memory Cache) ───[ HIT ]──┐
     │                                                        │ (< 10 ms)
     ▼ [ MISS ]                                               │
[ Resolution Layer & PoTokenStore ]                           │
     │ (poToken loaded in 0-2 ms from SharedPreferences)      │
     ▼                                                        │
[ InnertubeClient 350ms Hedged Race ]                         │
     │ ├── Candidate 1 (ClientWinnerStore priority)           │
     │ └── Candidate 2 (Hedged at t=350ms if needed)          │
     │ └── Shared OkHttpClient + 10min TTL DNS Cache          │
     ▼                                                        │
[ JsDecipherCache ] ──────────────────────────────────────────┘
     │ (Transforms cached per base.js hash; 24h disk TTL)     │
     ▼                                                        ▼
[ YtmHttpClient.preConnect() & just_audio Source Setup ]
     │ (Audio socket pre-warmed in background ConnectionPool)
     ▼
[ ExoPlayer Buffer Initialization ]
     │ (Tuned to 800ms-1200ms start threshold via AndroidLoadControl)
     ▼
[ First Audible Sound Output ] (PlaybackStage.playing)
```

---

## 3. How Tap-to-Sound Dropped from 10–15s to < 1s

| Task | Optimization | Latency Impact |
|---|---|---|
| **Task 0: Telemetry & Measurement** | Sentry spans + `PlaybackLatencyTracker` measuring every sub-stage. | Established ground-truth breakdown. |
| **Task 1: poToken Pre-warm & Persistent Store** | Persisted poToken to disk with 12h TTL and app-start pre-warming. | Saved **4.0 – 6.0 s** blocking WebView JS evaluation on every tap. |
| **Task 2: Resolved-stream LRU Cache** | 200-entry in-memory URL cache with safe expiry parsing and auto-retry. | Saved **2.5 – 4.0 s** on replaying tracks or switching back. |
| **Task 3: Next-track Pre-resolution** | Background resolver pre-resolves upcoming track based on queue & shuffle. | Reduced next-track transition to **< 300 ms**. |
| **Task 4: Hedged Racing & Client Winner Store** | Stripped slow TV client from stream chain; 350ms hedged race between fast clients. | Saved **3.0 – 5.0 s** serial client timeout cascade. |
| **Task 5: Innertube-First & Decipher Cache** | Direct Innertube player calls; cached signature decipher transforms (24h TTL). | Saved **1.5 – 2.5 s** heavy HTML/JS scraping per stream. |
| **Task 6: Shared OkHttp, DNS Cache & TLS Pre-connect** | Persistent HTTP/2 connection pool (max 8 idle, 5m keep-alive), 10m DNS TTL + DoH, socket pre-warm. | Saved **400 – 800 ms** TCP/TLS/DNS handshake latency. |
| **Task 7: Playback Start-Buffer Tuning** | Reduced start buffer from 2.5–5.0s to 800ms–1200ms via `AndroidLoadControl`. | Saved **1.5 – 3.5 s** waiting for buffer fill before sound. |

---

## 4. Troubleshooting Guide for Latency Regressions

### 4.1 How to Read `PlaybackLatencyTracker` Reports
Every track resolution logs a structured telemetry report:
```
[PlaybackLatencyTracker] trace_123 (videoId: dQw4w9WgXcQ) finished in 482ms [warm]
  - tap -> resolutionRequested: 8ms
  - resolutionRequested -> pluginEntered: 2ms
  - pluginEntered -> clientRequestSent: 1ms
  - clientRequestSent -> urlObtained: 220ms
  - urlObtained -> sourceSet: 35ms
  - sourceSet -> firstBytesReady: 180ms
  - firstBytesReady -> playing: 36ms
```

### 4.2 Common Regression Causes & Fixes

1. **`poTokenNeeded` takes > 1000 ms:**
   - *Cause:* poToken expired or was invalidated.
   - *Fix:* Verify `PoTokenManager.prewarm()` is executed on app start and `PoTokenStore` contains valid tokens (`PoTokenStore.isValid()`).
2. **`clientRequestSent -> urlObtained` spikes to > 2000 ms:**
   - *Cause:* Stored winning client encountered consecutive errors, falling back to full hedged race.
   - *Fix:* Check `ClientWinnerStore.getConsecutiveFailures(trackType, client)` or proxy latency.
3. **`urlObtained -> firstBytesReady` takes > 1500 ms:**
   - *Cause:* TLS socket handshake not pre-connected or network throughput throttled.
   - *Fix:* Verify `YtmHttpClient.preConnect(url)` was called upon stream resolution.
4. **Proxy Overhead:**
   - *Cause:* Proxy enabled on a slow proxy node.
   - *Fix:* When proxy is disabled, `ProxyManager.getProxy()` returns `null` with 0 ms overhead. When enabled, verify `ProxyPool` rotated dead nodes.

---

## 5. Verification Commands

Run the test suite to verify latency gates and flavor isolation:
```bash
# Dart Latency Regression Gate & Unit Tests
flutter test test/core/telemetry/latency_regression_gate_test.dart
flutter test test/data/audio/adaptive_buffer_engine_test.dart

# Android Hedged Resolution, Client Winner & OkHttp Tests
cd android
./gradlew :app:testDevDebugUnitTest

# GPL / Play Store Isolation Gate
./gradlew validateProdIsolation
```
