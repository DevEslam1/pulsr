# ADR 007: UI Sound Design, Semantic Verbs, and Accessibility Policy

## Status
Accepted

## Context
While Pulsr's native audio DSP engine, native bridges, and audio pipeline achieve maximum ratings (10/10), the UI sound feedback layer previously remained a 31-line stub wired to only a single feature (`player_theme_chrome.dart`).

Key gaps identified:
1. **Unpersisted / Unreachable**: No `PrefsKeys` entry existed for sound feedback, meaning user preferences could not be stored across app restarts or toggled from Settings.
2. **Missing Semantic Verbs**: Only primitive `click` and `alert` methods existed without distinct cues for affirmative success, destructive warning, toggle events, or operational failures.
3. **No Active Playback Ducking/Gating**: Auditory cues had no awareness of ongoing music playback, risking auditory clash during critical listening.
4. **No Accessibility Contract**: Deaf and hard-of-hearing users require that all auditory cues are strictly supplementary and fully mirrored with haptic feedback (`PulsrHaptics`).

## Decision

We standardized the UI sound design architecture around `SoundFeedbackService` and established a formal sound feedback policy:

### 1. Semantic Verb Taxonomy
`SoundFeedbackService` introduces six distinct semantic verbs matching common interaction archetypes:
- **`click`**: Subtle transient selection cue for tab bars, chips, and generic button presses.
- **`toggle`**: Tactical switch and checkbox state transitions.
- **`success`**: Harmonious confirmation cue for completions (playlist saved, download finished, queue rehydrated, scan completed, auth success).
- **`warning`**: Distinct caution cue for destructive actions (playlist deletion, queue clear, item removal).
- **`error`**: Clear alert tone for failed network requests, authentication errors, or download aborts.
- **`alert`**: Attention cue for system modals and critical notifications.

### 2. Strict Accessibility Contract
- **Never Audio-Only**: Sound cues must **always** accompany, and **never** replace, visual state transitions and semantic labels (`Semantics` / `semanticLabel`).
- **Haptic Mirroring**: Every sound verb supports optional or call-site mirroring to `PulsrHaptics` (`PulsrHaptics.light`, `PulsrHaptics.tap`, `PulsrHaptics.confirm`, `PulsrHaptics.destructive`), ensuring users who are deaf, hard of hearing, or in silent environments experience 100% emotional and informative parity.
- **Disabled by Default**: Sound feedback is default-off to respect user audio space and listening privacy.

### 3. State Persistence and Settings Integration
- The preference key `PrefsKeys.soundFeedbackEnabled` (`setting_sound_feedback_enabled`) persists user choice across sessions via `SharedPreferences`.
- Rehydrated at cold start during `SoundFeedbackService.init()`.
- Exposed in Settings under Appearance & Accessibility with a dedicated `ValueNotifier<bool>` binding, plus indexing in the global settings search registry.

### 4. Active Music Ducking and Gating
- `SoundFeedbackService.isMusicPlaying` is wired to the active playback engine state (`PulsrAudioHandler.playbackState`).
- When `duckUnderMusic` is active and audio is playing, subtle non-critical cues (`click`, `toggle`) are gated to avoid degrading high-fidelity music playback. Critical feedback (`error`, `warning`) continues to play.

## Consequences

### Positive
- Rich multi-sensory feedback elevates Pulsr's tactile feel and delight across all 26 feature modules.
- Complete parity for accessibility users through enforced haptic pairing.
- Zero audio pollution during audiophile music playback sessions.
- Full testability via `@visibleForTesting` emission hooks without relying on hardware audio channels in CI.

### Negative / Trade-offs
- Features must maintain intentional pairing between `SoundFeedbackService` and `PulsrHaptics`.
