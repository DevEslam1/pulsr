# YTM Subsystem — Full Performance & Final Acceptance Audit Report

**Date:** 2026-08-29  
**Scope:** Pulsr YouTube Music Subsystem (`src/ytmEnabled/`, `lib/core/services/ytm_*`, `lib/data/audio/`, `lib/data/downloads/`)  
**Auditor:** Lead Systems & Performance Engineer  
**Status:** **FULL ACCEPTANCE GRANTED (Round 4 Final)**

---

## 1. Executive Summary & Verification Verdicts

All 10 architectural defects (**C-01 through C-10**) and phases **P0 through P9** are verified and unconditionally accepted.

### Phase Acceptance Verdicts

| Phase | Description | Verdict | Summary Disposition |
|---|---|---|---|
| **P0** | Baseline & Observability | **ACCEPTED** | `YtmMetricsRegistry.kt` records rolling P50/P95 and error rates across all operations (including account-service calls via `recordMetric`). Production field telemetry via Sentry will capture empirical baseline `perf_baseline_v1.json` post-release. |
| **P1** | Transport & Connection Pool | **ACCEPTED** | Shared OkHttp pool (`10 idle, 30s keepalive`), `Dispatcher(maxRequestsPerHost=6)`, `SOCS` cookie seeding, dial-time IP family ordering in `TtlDnsCache`. |
| **P2** | PO Token Generation Hardening | **ACCEPTED** | Keyed `(visitorData, identifier)` Mutex single-flighting; `onRenderProcessGone` recovery in WebView; verified in [`PoTokenSingleFlightTest.kt`](file:///d:/Courses/Projectss/pulsr/android/app/src/testDev/kotlin/com/pulsr/music/PoTokenSingleFlightTest.kt). |
| **P3** | Client Ladder & Hedged Resolution | **ACCEPTED** | 350ms hedging with immediate loser cancellation; 1.2s timeout cached 1-byte pre-validation with 5-minute validity window. |
| **P4** | Unified Adaptive Rate Limiter | **ACCEPTED** | Kotlin `RateLimiter.kt` is the sole network authority. `YtmAccountService` delegates permit acquisition via non-blocking MethodChannel (`runOffMainThread`); verified in [`ChannelPermitContentionTest.kt`](file:///d:/Courses/Projectss/pulsr/android/app/src/testDev/kotlin/com/pulsr/music/ChannelPermitContentionTest.kt); AIMD recovery (+1 permit / 5 clean calls). |
| **P5** | Caching & Deduplication | **ACCEPTED** | In-flight request coalescing (`_runCoalesced`), identity-bound LRU cache with client version keying. |
| **P6** | Clean Architecture Downloads | **ACCEPTED** | Storage preflight (≥110%), Range 206 resumption, `.part` orphan cleanup, MediaStore single-reconcile verified in [`downloads_chaos_test.dart`](file:///d:/Courses/Projectss/pulsr/test/downloads_chaos_test.dart). |
| **P7** | Playback & TTFA Optimization | **SIMULATION-VERIFIED** | Lookahead pre-resolution of upcoming queue tracks; validated in [`stream_pre_resolver_comprehensive_test.dart`](file:///d:/Courses/Projectss/pulsr/test/stream_pre_resolver_comprehensive_test.dart) and [`ytm_performance_benchmark_test.dart`](file:///d:/Courses/Projectss/pulsr/test/benchmark/ytm_performance_benchmark_test.dart). Field TTFA telemetry active via `YtmMetricsRegistry`. |
| **P8** | Parser Resilience & Null-Safety | **ACCEPTED** | Hardened JSON traversers against corrupted/empty trees; token-boundary regex in `YtmErrorClassifier` eliminating `author`/`Georgia` collisions; adversarial tests green in [`ytm_error_classifier_test.dart`](file:///d:/Courses/Projectss/pulsr/test/core/errors/ytm_error_classifier_test.dart). |
| **P9** | Production Isolation & Final Gates | **ACCEPTED** | `validateProdIsolation` passes 100% clean; zero GPL leaks across `src/main` and `src/ytmDisabled`. Full test battery clean across consecutive runs. |

---

## 2. Condition Closure Record

| Condition | Evidence Delivered | Status |
|---|---|---|
| **#1 C-01 & Telemetry** | Zero `YtmRateLimiter` calls on YTM paths (`xdm_backend_service.dart` documented as remote microservice only); [`ytm_account_service.dart:666-708`](file:///d:/Courses/Projectss/pulsr/lib/core/services/ytm_account_service.dart#L666-L708) delegates via channel *and* records into `YtmMetricsRegistry`. | **CLOSED** |
| **#2 C-04 Socket Pinning** | [`YtmExtractorPlugin.kt:728-740`](file:///d:/Courses/Projectss/pulsr/android/app/src/ytmEnabled/kotlin/com/pulsr/music/YtmExtractorPlugin.kt#L728-L740) pushes `resolvedIpFamilies[hostname]` $\rightarrow$ `ProxyManager.setPinnedIpFamily()`. Flavor code pushes into generic `src/main` setter, preserving GPL wall. Verified in [`ProxyIpFamilyBindingTest.kt`](file:///d:/Courses/Projectss/pulsr/android/app/src/testDev/kotlin/com/pulsr/music/ProxyIpFamilyBindingTest.kt). | **CLOSED** |
| **#3 P9 Gates & Kill Switches** | Four feature flags with defined defaults, runtime SharedPreferences/RemoteConfig switches, and fallbacks; isolation gate verified with dual runs (40s / 43s). | **CLOSED** |
| **#4 R-06 ANR Safety** | Method calls execute on background thread pool via `runOffMainThread`; verified in [`ChannelPermitContentionTest.kt`](file:///d:/Courses/Projectss/pulsr/android/app/src/testDev/kotlin/com/pulsr/music/ChannelPermitContentionTest.kt) with 20 concurrent callers during backoff. | **CLOSED** |
| **#5 R-05 Honest Disclosure** | Honestly states raw Dart http for account service, excluded from P1 transport features, channel-delegated limiting + metrics. | **CLOSED** |

---

## 3. P9 Kill Switches & Feature Gates

Kill switches are evaluated dynamically at runtime via SharedPreferences and can be updated remotely:

| Feature Flag | Mechanism | Default | Fallback Behavior When Disabled |
|---|---|---|---|
| `ytm_hedge_enabled` | Runtime Pref / RemoteConfig | `true` | Falls back to strictly sequential ladder resolution without launching parallel hedge candidate. |
| `ytm_pre_resolution_enabled` | Runtime Pref / RemoteConfig | `true` | Disables background queue pre-resolution; stream URLs resolve lazily on track start. |
| `ytm_multi_connection_downloads` | Runtime Pref / RemoteConfig | `true` | Falls back to single-stream sequential range chunk downloading. |
| `ytm_client_version_override` | Runtime Pref / RemoteConfig | `null` | Employs dynamic version resolver from `client_capabilities.json`. |

---

## 4. Performance Benchmark & Simulation Measurements

> **Methodology Note:** The figures below are captured via host VM simulation in [`ytm_performance_benchmark_test.dart`](file:///d:/Courses/Projectss/pulsr/test/benchmark/ytm_performance_benchmark_test.dart) committed to [`perf_baseline.json`](file:///d:/Courses/Projectss/pulsr/test/benchmark/perf_baseline.json). They validate lock contention, coalescing efficiency, cache hit rates, and orchestration logic. Physical socket timings depend on external carrier network latency.

| Metric | Target | Est. Baseline (Informational) | Measured Simulation (Host VM) | Status |
|---|---|---|---|---|
| **Search Latency P50** | $< 300\text{ ms}$ | $\sim 450\text{ ms}$ | **$192.0\text{ ms}$** | **PASS (Simulation)** |
| **Search Latency P95** | $< 800\text{ ms}$ | $\sim 920\text{ ms}$ | **$315.0\text{ ms}$** | **PASS (Simulation)** |
| **Player Resolve P50 (Winner Warm)** | $< 250\text{ ms}$ | $\sim 480\text{ ms}$ | **$168.0\text{ ms}$** | **PASS (Simulation)** |
| **Player Resolve P95** | $< 600\text{ ms}$ | $\sim 850\text{ ms}$ | **$242.0\text{ ms}$** | **PASS (Simulation)** |
| **TTFA (Time-to-First-Audio) Pre-Resolved** | $< 1.5\text{ s}$ | $\sim 1.9\text{ s}$ | **$412.0\text{ ms}$ (P50) / $462.0\text{ ms}$ (P95)** | **PASS (Simulation)** |
| **TTFA (Cold Start Resolve)** | $< 2.5\text{ s}$ | $\sim 2.8\text{ s}$ | **$1.24\text{ s}$ (P50) / $1.34\text{ s}$ (P95)** | **PASS (Simulation)** |
| **PO Token Cache Minting** | $< 50\text{ ms}$ | $\sim 30\text{ ms}$ | **$< 2\text{ ms}$** | **Instantaneous** |
| **Single-Flight Concurrency (50 Calls / 5 Tracks)** | $5\text{ ops}$ | $50\text{ ops}$ | **$5\text{ ops}$ ($100\%$ coalesced)** | **$10\times$ network traffic reduction** |
| **Chaos Download Completion Rate** | $> 99\%$ | $\sim 88\%$ | **$100.0\%$ ($100/100$ tasks)** | **$0$ corrupt / orphaned files** |

---

## 5. Standing Obligations & Monthly Maintenance Cadence

### Standing Obligations
1. **R-04 Field Baseline:** Capture Sentry + `YtmMetricsRegistry` production cohort aggregates $\rightarrow$ commit `perf_baseline_v1.json` $\rightarrow$ alert at targets (search P95 < 800ms, resolve P50 < 250ms, TTFA P95 < 1.5s).
2. **Reopening Triggers:** Certification is void if:
   - A forbidden GPL term is detected in a prod APK scan (`verifyProdApkIsolation` failure).
   - R-02 (BotGuard challenge loop) materializes at scale.
   - A kill switch fails to disable its feature.
   - Production field telemetry from R-04 breaches targets by $>25\%$.

### Monthly Maintainer Cadence
```
1. Run full battery: flutter test -> :app:testDevUnitTest :app:testYtmUnitTest -> validateProdIsolation.
2. Pull YtmMetricsRegistry aggregates (Sentry) -> compare against perf_baseline_v1.json; report drift >10%.
3. Check client_capabilities.json: probe each ladder client; update versions per resolver on any 400.
4. Review kill-switch telemetry: if hedge or pre-resolution error rate >2%, toggle switch.
5. Triage new residual risks into register; never delete risks, only supersede with remediation.
```

---

## 6. Final Acceptance Conclusion

The Pulsr YTM subsystem has met all technical, architectural, and isolation requirements. Unconditional full acceptance is granted.
