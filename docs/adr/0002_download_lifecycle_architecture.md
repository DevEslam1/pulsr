# ADR 0002: Pulsr Music Download Lifecycle Architecture

## Status
**Accepted & Implemented**

## Context
Pulsr Music provides robust offline playback by downloading YouTube Music streams and local audio files into the device storage while respecting strict Android foreground service policies (Android 14+ / API 34 dataSync FGS and Android 15 / API 35 6-hour cumulative quota limits), Clean Architecture boundaries, and production flavor isolation (zero GPL/extractor references in prod).

---

## Download Lifecycle Flow

```
[ User Action: Queue / Batch ]
             │
             ▼
[ 1. Ingestion & Preflight ]
   ├── Deduplicate by videoId
   ├── Verify Disk Space (ENOSPC Preflight)
   └── Request POST_NOTIFICATIONS (API 33+)
             │
             ▼
[ 2. Stream URL Resolution & TTL ]
   ├── Check YtmUrlCache (LRU In-Memory Cache)
   ├── Hedged Client Resolution (Innertube)
   └── Store resolvedAt & etag on DownloadTask
             │
             ▼
[ 3. Worker Pool & Resilient Download ]
   ├── Concurrency Cap (Max 3 parallel workers)
   ├── Foreground Service (dataSync) + StartNotAllowed Guards
   ├── HTTP Range Resume + 206 Validation + ETag matching
   ├── 250ms / 1% Throttled Progress Updates
   └── 30s Zero-Bytes Stall Watchdog
             │
             ▼
[ 4. Tagging Stage ]
   └── Jaudiotagger ID3/MP4 Metadata & Artwork Embedding
             │
             ▼
[ 5. Storage & Indexing Stage ]
   ├── Atomic rename from .part to final target
   ├── MediaStore Content URI Indexing (Android 10+)
   └── Single-pass Sync in MusicRepository
             │
             ▼
[ 6. Post-Download & Lifecycle Reconciliation ]
   ├── Reconcile on Boot ('downloading' -> 'interrupted')
   ├── Sweep orphaned .part files older than 10 minutes
   └── Invalidate and update StorageStats cache
```

---

## Invariants & Design Principles

1. **Clean Architecture Isolation**:
   - `Presentation` (`DownloadsCubit`, `DownloadsScreen`) $\leftrightarrow$ `Domain` (`QueueDownloadUseCase`, `IDownloadRepository`) $\leftrightarrow$ `Data` (`DownloadRepositoryImpl`, `YtDownloadService`).
   - Domain has zero Flutter dependencies; presentation never imports data layer directly.
2. **Flavor Hygiene**:
   - YouTube extraction code lives exclusively in `src/ytmEnabled` and Dart `ENABLE_YTM` flag.
   - `prod` flavor compiles with zero YouTube dependencies.
3. **Resilience & Storage Safety**:
   - Stale `.part` files are automatically pruned after 10 minutes.
   - Partial file downloads check server `206 Partial Content` before appending; corrupted or ignored ranges reset cleanly.
   - 6-hour dataSync timeout on Android 15 flushes in-flight state to persistent storage and gracefully terminates.
