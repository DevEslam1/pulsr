# ADR 004: Dual-Tier WeakReference Artwork Cache

## Status
Accepted

## Context
High-resolution album artwork loaded during continuous scrolling and rapid track changes caused substantial memory pressure:
1. **Unbounded Strong References**: In-memory caches holding hard references to `Uint8List` image byte buffers prevented garbage collection, leading to Out-Of-Memory (OOM) crashes on low-RAM devices during long sessions.
2. **Cache Thrashing**: Strictly sizing a small LRU cache evicted images too quickly when the user scrolled back and forth, resulting in repetitive disk/network requests and UI stutters.

## Decision
We implemented a dual-tier caching strategy combining bounded strong LRU caching with garbage-collection-aware `WeakReference` storage in `lib/core/widgets/cached_artwork.dart` (`ArtworkCacheManager`):

```
┌────────────────────────────────────────────────────────┐
│               Artwork Request (Key)                    │
└─────────────────────────┬──────────────────────────────┘
                          │
                          ▼
            ┌───────────────────────────┐
            │  Tier 1: Bounded LRU      │ ─── Hit ──► Return Bytes
            │  Strong Reference Cache   │
            │  (Ceiling: maxBytes/maxCt)│
            └─────────────┬─────────────┘
                          │ Miss
                          ▼
            ┌───────────────────────────┐
            │  Tier 2: WeakReference    │ ─── Hit ──► Promote to LRU
            │  Ephemeral Memory Cache   │             Return Bytes
            │  (Auto GC reclaimed)      │
            └─────────────┬─────────────┘
                          │ Miss
                          ▼
            ┌───────────────────────────┐
            │  Tier 3: Disk / Network   │ ─── Fetch ─► Populate T1 & T2
            └───────────────────────────┘
```

### Architecture
- **Tier 1 (Strong LRU)**: Retains recently accessed images up to a strictly bounded byte budget (default 32MB) and count budget. When exceeded, the oldest items are evicted from the strong LRU.
- **Tier 2 (WeakReference)**: Evicted items remain accessible in memory via `WeakReference<Uint8List>` as long as the Dart GC has not reclaimed them. If requested again while in memory, they are immediately promoted back to Tier 1 without disk or network I/O.
- **Dynamic Type & Target Sizing**: Caches downscaled thumbnails (220x220) for playlist lists and full resolution for full-screen player views.

## Consequences
### Positive
- Memory footprint is strictly bounded; total strong cache usage never exceeds the configured threshold.
- Zero premature network/disk reloading when browsing recently scrolled albums that haven't been GCed yet.
- Zero OOM crashes on memory-constrained Android devices (verified in `test/lifecycle/disposal_audit_test.dart`).

### Negative / Trade-offs
- Dereferencing `WeakReference.target` requires handling null when GC has reclaimed the object, requiring clean fallback to disk/network fetching.
