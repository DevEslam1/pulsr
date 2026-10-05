# ADR 008: Declarative Routing with go_router

## Status
Accepted

## Context
Pulsr needs navigation across a five-tab shell (Home, Library, Search, Playlists, Settings) plus many full-screen destinations (now-playing, album/artist/genre/year detail, playlists, tag editor, theme studio, YTM surfaces). Requirements:
1. **Deep links and restoration**: detail pages must be reachable from an id alone, not only from an in-memory object.
2. **Build gating**: YouTube-Music-dependent routes must not exist in builds where YTM is disabled.
3. **Predictable transitions** that respect Reduce Motion.
4. **Fewer navigation bugs**: double-taps pushing duplicate pages, orphaned routes and unhandled not-found states.

## Decision
We use `go_router` with a single router definition in `lib/core/router/app_router.dart` (`createRouter`) plus helpers in `lib/core/router/safe_navigation.dart`.

### 1. Shell + branch structure
- `StatefulShellRoute.indexedStack` hosts the five tab branches, keeping each tab's navigation stack alive across switches.
- `rootNavigatorKey` is a top-level `GlobalKey<NavigatorState>`; full-screen routes set `parentNavigatorKey: rootNavigatorKey` so they cover the shell (mini-player aware).

### 2. Typed `extra` with id fallback
Detail routes prefer a typed object passed via `state.extra` (no refetch, preserves `heroTag`), and fall back to an `?id=` query/path parameter. `_resolveById<T>` builds `EntityByIdLoader` which fetches-or-watches the entity reactively and renders a localized not-found message when the id is absent or matches nothing.

### 3. Build gating and redirects
- YTM routes (`/ytm-search`, `/ytm-explore`, `/downloads`) are wrapped in `if (AppConfig.ytmEnabled)` so they tree-shake away in pure builds, and a top-level `redirect` also bounces those paths (plus `/online-playlist`) when disabled.
- `/cloud-backup-dashboard` redirects to `/settings` unless cloud sync is allowed, so a dead surface is never shipped.
- A global `errorBuilder` renders a localized "page not found" with a home action.

### 4. Motion-aware transitions
Custom `CustomTransitionPage` builders (`_buildPulsrPageRoute` for detail pushes, `_buildTabPage` for tab switches) short-circuit to the raw child when `context.motionEnabled` is false, so Reduce Motion users get instant navigation.

### 5. Safe push
`PulsrSafePush.pushDebounced` collapses repeat pushes to the same location within a 600 ms window, keyed on destination (not widget), so a fast double-tap cannot stack two identical pages.

## Consequences
### Positive
- Every detail screen is deep-linkable/restorable through its id.
- YTM and cloud surfaces are compile-time or redirect-gated, never dead links.
- Consistent, accessible transitions honour Reduce Motion in one place.
- `pushDebounced` removes a common duplicate-navigation class of bug.

### Negative / Trade-offs
- Route builders embed some screen-specific argument unpacking, so adding a route touches `app_router.dart`.
- `extra` is not restored across process death; the id fallback is what makes restoration work, and only routes with an id fallback restore cleanly.
