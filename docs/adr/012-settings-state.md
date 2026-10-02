# ADR 012: Settings State Management

## Status
Accepted

## Context
Settings is the widest state surface in Pulsr: playback transport, theming, accessibility, proxy, audiophile output, DSP, telemetry and experience-mode flags. Requirements:
1. **Many independent fields** with sensible defaults, updated often, without hand-written `copyWith` boilerplate drifting from the field list.
2. **Backward-/forward-compatible persistence** so a new setting does not break an existing install.
3. **Proxy secrets must not sit in plain preferences.**
4. **Concurrency safety**: load and migration run concurrently with UI actions, and a naive read-modify-write can drop updates.
5. **A curated vs. full control surface** (Normal vs. Professional).

## Decision
Settings is a Freezed value class driven by a `SettingsCubit`.

### 1. Immutable, generated state
`SettingsState` (`lib/features/settings/cubit/settings_state.dart`) is `@freezed` with `@Default(...)` per field, giving `copyWith`, `==`/`hashCode` and explicit defaults for free. Enums it embeds (`AppThemeMode`, `ThemeColorSource`, `PlayerThemeMode`, `ReplayGainMode`, `DsdOutputMode`, `ExperienceMode`, `VisualizerStyle`, `ProxyEntry`, `AudioOutputInfo`, …) are part of the value. `SettingsState._()` declares computed getters (`customAccentColor` with a cached `Color`, `isProfessional`, `dynamicThemingEnabled`, `audibleLatencyOffset`).

### 2. Experience modes
`ExperienceMode.normal` (default) hides advanced DSP/output controls and runs Smart Audio defaults; `ExperienceMode.professional` reveals the full surface. `isProfessional` is the single gate consumed by the UI.

### 3. Persistence
Each setting maps to a `PrefsKeys`/`SharedPreferences` entry; unknown/missing keys fall back to the field default, which is what makes old profiles load and new settings safe. Proxy **passwords** do not live in the state: only `hasProxyPassword` is exposed, and the secret is held in `FlutterSecureStorage`.

### 4. Concurrency
`SettingsCubit` guards its critical read-modify-write paths with `Mutex` (`_migrationMutex` for migration verification, `_loadMutex` for load), so a concurrent load cannot interleave with a migration/action and clobber state. Profile lists and device links similarly serialize their prefs read-modify-write (see ADR 014). This is a targeted use of a mutex, not a blanket one.

### 5. Error surfacing
The state carries an optional `errorMessage` for recoverable UI errors instead of throwing out of the cubit.

## Consequences
### Positive
- Adding a setting is a one-line field plus its persistence key; generated `copyWith`/equality cannot drift from the fields.
- Defaults make both old and new persisted data load safely.
- Secrets stay out of the state and out of ordinary preferences.
- Targeted mutexes prevent lost-update races on load/migration and profile writes.

### Negative / Trade-offs
- A very wide `SettingsState` means many fields rebuild consumers unless they select narrowly.
- Freezed generated file (`settings_state.freezed.dart`) must be regenerated after edits.
- Migrations must remain inert when the prefs are already current.
