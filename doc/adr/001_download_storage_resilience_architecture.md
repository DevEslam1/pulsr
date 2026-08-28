# ADR 001: Audio Downloads Storage, Lifecycle, and Resilience Architecture

## Status
**Accepted & Implemented**

## Context
Pulsr allows users to download offline music streams from YouTube Music. To provide a **10/10 offline experience**, the download subsystem must guarantee:
1. **Zero-corruption**: Partial or aborted downloads must never result in corrupted library entries or audio glitches.
2. **Foreground Service Compliance**: Respect Android 14/15 Foreground Service dataSync limits (API 35 6-hour execution caps) while preventing Doze sleep stalls.
3. **Scoped Storage Compliance**: Work seamlessly across Android 9 (API 28) through Android 15+ (API 35+) without `SecurityException` or requiring deprecated broad permissions.
4. **Clean Architecture Boundaries**: Ensure domain use cases remain decoupled from platform services and UI layers.

---

## Architectural Decisions

### 1. Storage Strategy: MediaStore Contributed Audio
- **Android 10+ (API 29+)**: All completed audio streams are written directly to `MediaStore.Audio.Media.EXTERNAL_CONTENT_URI` using the application's contributed scoped storage. Files are inserted with `IS_PENDING = 1`, streamed, and updated to `IS_PENDING = 0` upon full byte validation.
- **Android 9 (API 28)**: Falls back to `Environment.DIRECTORY_MUSIC` with atomic file copy and immediate `MediaScannerConnection.scanFile` indexing.
- **Path Sanitization**: Filenames are strictly sanitized with `[<>:"/\\|?*\x00-\x1F]` stripping, Windows reserved name checks (`CON`, `PRN`, `AUX`, `NUL`, etc.), and 180 UTF-8 byte caps.

### 2. Multi-Part & Resume Durability
- **206 Partial Content Verification**: If a `Range` request is dispatched, the server must reply with HTTP 206. If HTTP 200 is returned, the partial `.part` file is discarded to prevent corrupted byte concatenation.
- **Multi-chunk Parallel Downloads**: High-speed multi-threaded downloads (4 concurrent chunks) write to discrete `.part0..3` temporary files, verified for total byte sum and fsynced before atomic rename.
- **Backoff + Jitter**: YouTube 429 rate limits parse `Retry-After` headers and apply exponential backoff `(1000 * (1 << (attempt - 1))) + jitter`.

### 3. Lifecycle & Zombie Row Startup Sweep
- **Process Death Reconciliation**: On boot, `DownloadRepositoryImpl.reconcileOnBoot()` converts orphaned `downloading` or `queued` tasks to `paused`.
- **Orphan Part Cleaner**: Deletes non-active `.part` files older than 10 minutes while preserving active paused partials.
- **Android 15 (API 35) FGS Timeout**: `DownloadTimeoutHandler` handles `Service.onTimeout()` by flushing partial progress and cleaning zero-byte files.

### 4. Bounded Concurrency & Queue Prioritization
- **Semaphore**: Hard-capped at 3 concurrent downloads.
- **Queue Operations**: Supports FIFO batch enqueueing, priority boosting (`prioritizeDownload`), and dynamic queue re-ordering (`reorderQueue`).

---

## Layer Verification & Quality Gates
- `test/di/injection_graph_test.dart` enforces layer separation (Domain has 0 imports of Data/Features; Data/Core have 0 imports of Features).
- `test/downloads_chaos_test.dart` simulates interleaved random pauses, process kills, and airplane mode toggles across 100-item queues with 0 corrupt finals.
