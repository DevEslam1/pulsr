# Audit — User-Facing Frontend Options: Inventory, Wiring, Benchmark Gaps

**Repo:** `D:\Courses\Projectss\pulsr` · Flutter UI via vendored `package:material_ui/material_ui.dart`
**Scope:** every user-facing presentation option reachable from Settings, Now Playing, Home and the shell; how each is stored and whether it actually reaches a widget.
**Method:** static read of the settings tree (`lib/features/settings/presentation/**`, 58 files), the 11 player themes + Theme Studio, shell dock/nav, mini player, lyrics view, theme pipeline (`lib/core/theme/**`, `main.dart`), plus repo-wide greps to prove or disprove that each stored key has a reader. No app was run; no profiling. Claims that needed a device (visual output, perf) are marked **unverified**.
**Date:** 2026-11-18

---

## 0. Headline

Pulsr's option surface is unusually wide for a Flutter music player — 11 player themes with live previews, three accent sources, an AMOLED mode, calm/comfortable density, glass intensity, a full gesture-remap set, four dock styles, per-track lyric offset, headset-click remapping and importable visualizer presets. The wiring is mostly real: `main.dart` genuinely rebuilds the theme from `SettingsCubit`, `PulsrMotion` genuinely collapses animation from one flag, and gestures are genuinely read at the point of use.

The defects are not "fake settings" so much as **options that promise more than they deliver, or that live outside the settings system**:

- **Theme Studio is orphaned.** It is reachable only from Home → *Browse more tools* (`home_screen.dart:625`), not from Settings, and searching "studio" in Settings routes to Experience Mode instead (`search_results_section.dart:1084`).
- **Theme Studio's radius/glow are conditionally inert.** They apply only when accent source is `custom` (`player_shape.dart:13-20`), but the Studio's own preview frame rounds regardless (`custom_theme_builder_screen.dart:338`), so the slider looks live while the player ignores it.
- **"Button Style" does not touch buttons.** `AuraTheme` hard-codes `AppRadii.buttonRadius` for Filled/Elevated/Outlined (`aura_theme.dart:1002-1060`); the setting only reaches chips, section headers and the queue switcher (9 call sites).
- **Backup/restore drops most appearance options** and writes an orphan bit-perfect key (`backup_usecases.dart:123,780`).

---

## 1. How to read the inventory

**Applied?** column traces the chain `surface → setter → storage → consumer`.

| Mark | Meaning |
|---|---|
| ✅ | Toggle/setter is persisted **and** read by the widget or service that renders the effect |
| ⚠ | Applied, but with a caveat that changes what the user gets (conditional, restart-gated, partially reaching the UI) |
| ❌ | No effect on the UI |

**Flag** column follows the brief's taxonomy, plus two additions I needed:

| Flag | Meaning |
|---|---|
| **(a)** | Dead: stored and never read, or present in UI with no write path |
| **(b)** | Read/used but not persisted (resets on rebuild/restart) |
| **(c)** | Half-applies: changes some surfaces, not the ones the label implies |
| **(d)** | Duplicate/conflicting: two controls for one decision, or one control silently overwritten by another |
| **(p)** | Missing/partial option relative to the benchmark set (not a bug — a coverage gap) |

---

## 2. Option inventory

### 2.1 App appearance & theming

| ID | Option | Where surfaced | Storage key | Applied? (trace) | Flag |
|---|---|---|---|---|---|
| A1 | Theme mode: System / Light / Dark / AMOLED | Settings → Look → segmented control `appearance_section.dart:37-93` | `setting_theme_mode` | ✅ `setThemeMode` `settings_cubit.dart:1459` → `main.dart:1346-1352` maps to `ThemeMode`, passes `isAmoled` to `AuraTheme.customTheme` `main.dart:1334` | — |
| A2 | Accent swatches (`AppColors.customAccents`) | Same section, horizontal palette `appearance_section.dart:93-190` | `setting_custom_accent` (+ forces `setting_theme_color_source=custom`) | ✅ `setCustomAccentColor` `settings_cubit.dart:1526-1545` → `main.dart:1285-1288` `resolveAccent` | — |
| A3 | Accent source: wallpaper / artwork / custom | Look → nav tile `appearance_section.dart:244` → sheet `settings_theme_pickers.dart:1109` | `setting_theme_color_source` | ✅ `setThemeColorSource` `settings_cubit.dart:1398-1404` → `main.dart:1276-1289`; artwork path fed by `DynamicThemeCubit` palette extraction | — |
| A4 | "Dynamic theming" boolean (legacy) | No direct UI | `setting_dynamic_theme` | ⚠ Read only as a migration fallback when the source key is absent (`settings_cubit.dart:405`), written as a mirror of A3 (`:1403`) | **(d)** two keys for one decision |
| A5 | Auto dark by time | Look → switch `appearance_section.dart:182` | `setting_auto_theme_by_time` | ✅ `setAutoThemeByTime` `:1470` → `ThemeScheduleController` → `ThemeSchedulerService` night stream → `setThemeMode` | — |
| A6 | Dark-hours window | Inline `ThemeScheduleRow` (shown only when A5 on) | `setting_theme_schedule_start` / `_end` | ✅ `ThemeScheduleController.setHours` `theme_schedule_controller.dart:80-95`; restored on cold start `:100-110` | — |
| A7 | High contrast | Look → Accessibility `appearance_section.dart:351` | `setting_high_contrast` | ✅ `main.dart:1316-1327` → `AuraTheme.highContrastThemeFor`; also ORs OS `MediaQuery.highContrastOf` `:1291` | ⚠ forces dark system-chrome (see F5) |
| A8 | Dim white point (eye comfort) | Accessibility `appearance_section.dart:360` | `setting_dim_white_point` | ⚠ `AuraTheme` applies only in dark, non-high-contrast (`aura_theme.dart:571,611`); silently ignored in light and in high contrast, with no disabled state | **(c)** |
| A9 | Visual density: Comfortable / Calm | Look → segmented `appearance_section.dart:274-330` | `setting_visual_density_mode` | ✅ `setVisualDensityMode` `settings_accessibility_ext.dart:53` → `main.dart:1298` `isCalmDensity` → `AuraTheme` alpha table + `p.isCalmDensity` in nav/mini/home cards | — |
| A10 | Glass intensity 0–100 % | Accessibility slider `appearance_section.dart:433-500` | `setting_liquid_glass_tint` | ⚠ `GlassContainer` reads it live (`glass_container.dart:126,146-152`) and nav dock too (`bottom_nav_bar.dart:315-330`); but only ~4 surfaces actually blur app-wide (consistent with `audit/frontend/blur-depth.md` F1) | **(c)** |
| A11 | Reduce motion | Accessibility `appearance_section.dart:369` | `setting_reduce_motion` | ✅ `settings_accessibility_ext.dart:18-27` → `GpuBudget` + `main.dart:1386-1389` rewrites `MediaQuery.disableAnimations`; honoured by `PulsrMotion.resolve` | ⚠ also disables shaders/blur (see F6) |
| A12 | Haptics | Accessibility `appearance_section.dart:378` | `setting_haptics_enabled` | ✅ `PulsrHaptics.setEnabled` + cold-start restore (`settings_accessibility_ext.dart:29-48`) | — |
| A13 | UI sound effects | Accessibility `appearance_section.dart:390` | `SoundFeedbackService` own key | ✅ `SoundFeedbackService.enabledNotifier` (service-owned channel, bypasses `SettingsCubit`) | ⚠ parallel store |
| A14 | Spotify Canvas / motion artwork | Accessibility `appearance_section.dart:401` | `setting_canvas_enabled` | ✅ `now_playing_screen.dart:205-212` `CanvasBackdrop` | — |
| A15 | Full-screen ambient backdrop | Accessibility, nested under A14 `:407-420` | `setting_canvas_as_backdrop` | ✅ same widget, `isBackdropMode: true` | — |
| A16 | Language: System / English / Arabic / Spanish | Look → nav tile `appearance_section.dart:324` → sheet `settings_theme_pickers.dart:989-1090` | `setting_language_code` | ⚠ `main.dart:1404-1406` sets `locale` (null for `system`) and `<ar>` ships RTL; but the media notification treats the literal string `system` as a language code (`audio_handler.dart:140-142`), so choosing *System* on an Arabic device leaves the notification channel English | **(c)** + F3 |
| A17 | In-app text size / UI scale | — | — | ❌ Absent. Only OS scaling, clamped 0.8–2.0 (`main.dart:1392-1399`) | **(p)** |
| A18 | Bold text | — (no control) | — | ✅ OS `boldText` is forwarded into `AuraTheme.customTheme(isBoldText:)` `main.dart:1295` — good citizenship, but no in-app option | — |

### 2.2 Player themes & Theme Studio

| ID | Option | Where surfaced | Storage key | Applied? (trace) | Flag |
|---|---|---|---|---|---|
| P1 | Now Playing theme (11: Classic, Card, Circle, Minimal, Vinyl, CD, Cassette, Full-bleed waveform, Karaoke/lyrics, Clean, Milkdrop) | Look → nav tile `appearance_section.dart:195` → live-preview carousel + list `settings_theme_pickers.dart:376-560` | `setting_player_theme_mode` | ✅ `setPlayerThemeMode` `settings_cubit.dart:1585` → `ThemeRegistry.build` `theme_registry.dart:21-31` → `now_playing_screen.dart:196` | — |
| P2 | Theme Studio (open) | **Home → Browse more tools → Theme Studio** only (`home_screen.dart:625`; route `app_router.dart:843`) | — | ✅ Screen renders | **(c)** not in Settings, not in search |
| P3 | Studio accent palette (7 swatches) | Studio `custom_theme_builder_screen.dart:380-430` | `setting_custom_accent` + source override | ✅ `setCustomAccentColor` (same key as A2) | **(d)** overlaps A2 with a different 7-colour list |
| P4 | Studio corner radius 0–48 | Studio slider `:510-531` | `setting_custom_theme_radius` | ⚠ Read by `resolveCustomRadius` `player_shape.dart:13-20`, chrome `player_theme_chrome.dart:576-578, 766-773` — **only when `themeColorSource == custom`**; Studio's own preview frame rounds regardless (`custom_theme_builder_screen.dart:338`) | **(c)** silent no-op |
| P5 | Studio ambient glow | Studio switch `:536-548` | `setting_custom_theme_glow` | ⚠ Same gate `player_shape.dart:24-32` | **(c)** |
| P6 | Studio JSON import / export | Studio app-bar actions `:60-230` | none (applies to A2/P4/P5 on import) | ✅ Import writes prefs via `setCustomAccentColor` / `setCustomThemeRadius` / `setCustomThemeGlow`; export is share-sheet JSON | **(b)** no named theme library — one slot only |
| P7 | Seek-bar slider style: Normal / Wavy / Capsule / Minimal | Look → nav tile `appearance_section.dart:205` | `setting_player_slider_style` | ✅ `player_seek_bar.dart:421`, `tablet_player_bar.dart:121-127`, `clean_player_theme.dart:219` | **(d)** exclusive with P8-waveform; cubit silently rewrites (`settings_cubit.dart:1562-1576`) |
| P8 | Button style: Classic / Rectangular / Capsule | Look → nav tile `appearance_section.dart:220` | `setting_app_button_style` | ⚠ `pulsr_button_style.dart:14-38` consumed by chip/section-header/discovery-chip/queue-switcher/lyrics chips only (9 sites); Material buttons fixed at `AppRadii.buttonRadius` (`aura_theme.dart:1002-1060`) | **(c)** label overpromises |
| P9 | Visualizer style: Off / Bar / Wave / Circular / Particles / 3D terrain / Milkdrop / Custom | Look → nav tile `appearance_section.dart:234` | `setting_visualizer_style` | ⚠ Honoured by 8 of 11 themes (Classic, Card, Circle, CD, Cassette, Clean, Waveform, Milkdrop); **Vinyl, Minimal, Karaoke ignore it** (no `AudioVisualizer` reference in `vinyl_player_theme.dart` / `minimal_player_theme.dart`) | **(c)** |
| P10 | Visualizer preset import (Milkdrop `.milk` / Pulsr JSON) | Visualizer picker tail `settings_theme_pickers.dart:1360-1440` | `VisualizerPresetStore` / `MilkdropPresetStore` own keys | ✅ `audio_visualizer.dart:247` loads preset; import also flips style to `milkdrop` / `custom` | ⚠ no preview before applying |
| P11 | Dock stacking style: Default / System / Mini player on top / Nav bar on top | Look → nav tile `appearance_section.dart:256` → `DockStylePickerSheet` | `setting_dock_stack_mode` | ✅ `DockStyleController` (static `ValueNotifier`) → `app_shell.dart:398-404` `StackedBottomDock` | ⚠ outside `SettingsState` (see F7) |
| P12 | Nav bar labels on/off | — | — | ❌ `iconOnly` exists but is hard-coded `true` in one layout (`stacked_bottom_dock.dart:458`); no user control | **(p)** |

### 2.3 Navigation, mini player & gestures

| ID | Option | Where surfaced | Storage key | Applied? (trace) | Flag |
|---|---|---|---|---|---|
| G1 | Mini player swipe-left action: Next / Previous / Volume / None | Look → Gestures `gestures_section.dart:24-36` | `setting_mini_player_swipe_left` | ✅ `mini_player.dart:418-421` + action dispatch `:103-120` | ⚠ queue carousel only when left=Next **and** right=Previous (`mini_player.dart:421-424`) |
| G2 | Mini player swipe-right action | `gestures_section.dart:36-48` | `setting_mini_player_swipe_right` | ✅ same | ⚠ same |
| G3 | Mini player visual style (size / art / progress / compact) | — | — | ❌ Absent. Mini player only reacts to the *vinyl* theme (`mini_player.dart:777-780`); CD/Cassette/Clean/Milkdrop do not change it | **(p)** |
| G4 | Now Playing double-tap: Favorite / Lyrics / None | `gestures_section.dart:51-58` | `setting_now_playing_double_tap` | ✅ `player_gesture_scope.dart:29-56` | — |
| G5 | Artwork swipe: Next/Previous or None | `gestures_section.dart:62-70` | `setting_now_playing_artwork_swipe` | ✅ `player_gesture_scope.dart:64` | — |
| G6 | Headset single press action | Sound → headset section `headset_controls_section.dart:186-200` | `setting_headset_single_click` | ✅ `HeadsetControlConfig.load` `headset_control_config.dart:51-70` → `audio_handler_transport.dart:491` | — |
| G7 | Headset double press action | `:202-212` | `setting_headset_double_click` | ✅ same | — |
| G8 | Headset triple press action | `:214-224` | `setting_headset_triple_click` | ✅ same | — |
| G9 | Multi-press window 150–800 ms | `:226-250` | `setting_headset_click_window_ms` | ✅ same | — |
| G10 | Headset seek step 5–60 s | `:252-276` | `setting_headset_seek_seconds` | ✅ same | — |
| G11 | Auto-resume after headset reconnect | `:120-140` | `setting_auto_resume_on_reconnect` | ✅ `audio_handler.dart:1041-1053` | — |
| G12 | Reconnect resume window 15–300 s | `:142-170` | `setting_auto_resume_timeout_sec` | ✅ same | — |
| G13 | Keep media notification after pause | `:172-186` | `setting_keep_notification_on_pause` | ⚠ `audio_handler.dart:138` reads it at `AudioService.init` — takes effect only on next cold start (the tile says so) | ⚠ restart-gated |
| G14 | Gesture guide sheet | `gestures_section.dart:18-24` | — | ✅ informational sheet | — |

### 2.4 Library & list presentation

| ID | Option | Where surfaced | Storage key | Applied? (trace) | Flag |
|---|---|---|---|---|---|
| L1 | Hidden / excluded folders | Library → nav tile `library_section.dart:18` → `/hidden-folders` | Drift `ExcludedFoldersTable` | ✅ scanner consumes exclusions; screen at `hidden_folders_screen.dart` | — |
| L2 | Auto-hide system ringtones/notifications | Hidden folders screen `hidden_folders_screen.dart:229`; also surfaced as the subtitle in `library_section.dart:24` | `setting_auto_hide_system_media` | ✅ `main.dart:916` → `MediaScannerService` (`media_scanner_service.dart:911,1053`) | — |
| L3 | Rescan library + live % | `library_section.dart:26-70` | — | ✅ `cubit.rescanLibrary()` + `scanProgress` stream | — |
| L4 | Short-audio filter (min duration) | `library_section.dart:86-92` | `setting_min_duration` | ✅ scanner | — |
| L5 | Rebuild search index | `:96-108` | — | ✅ `cubit.rebuildSearchIndex()` | — |
| L6 | Remove missing files | `:110-115` | — | ✅ repository prune | — |
| L7 | Fetch missing artwork | `:117-124` | — | ✅ `MissingArtworkService` | — |
| L8 | List density (comfortable / compact / artwork-only) | — | — | ❌ Absent; only hard-coded `VisualDensity.compact` in a few tabs (`library_songs_tab.dart:158`) | **(p)** |
| L9 | Cover-art source preference (embedded / folder / online) | — | — | ❌ Absent; `missing_artwork_service` fetches, but there is no source priority option | **(p)** |

### 2.5 Playback & audio behaviour (frontend-visible)

| ID | Option | Where surfaced | Storage key | Applied? (trace) | Flag |
|---|---|---|---|---|---|
| B1 | Gapless | Sound → Playback `playback_section.dart:75` (also duplicated in pro variant `:184`) | `setting_gapless` | ✅ handler; mutually exclusive with crossfade (`settings_cubit.dart:1314-1363`) | **(d)** conflict handled, but disabled-state only |
| B2 | Crossfade 0–12 s | `:102-131` | `setting_crossfade` | ✅ `CrossfadeManager` | — |
| B3 | BPM-synced crossfade | Professional diagnostics `audio_diagnostic_section.dart:96` | `setting_bpm_sync_crossfade_enabled` | ✅ `audio_handler.dart:2211` | ⚠ buried two levels down |
| B4 | Waveform seek bar | `playback_section.dart:96` | `setting_waveform_seek_bar` | ✅ `player_seek_bar.dart:170`; forces slider style to Normal and vice-versa (`settings_cubit.dart:1417-1429, 1562-1576`) | **(d)** |
| B5 | Resume after interruption | `:87` | `setting_resume_after_interruption` | ✅ `playback_interruption_manager` | — |
| B6 | Automix / smart transitions | `:257` | `setting_automix_enabled` | ✅ `audio_handler.dart:581, 2713`; `audio_handler_queue_engine.dart:430` | — |
| B7 | Hedged stream resolution | `:267` | `hedged_resolution_enabled` | ✅ streaming layer | — |
| B8 | Adaptive runtime quality | `:277` | `adaptive_quality_enabled` | ✅ streaming layer | — |
| B9 | Silence-skip sensitivity 0–3 | `:284` | `skip_silence_sensitivity_v1` | ✅ `audio_handler_playback_extras.dart:235` | — |
| B10 | Ducking mode (duck / pause) | `:299` | `audio_ducking_mode_v1` | ✅ `ducking_controller` + `main.dart:772` | — |
| B11 | Ducking level | `:304-312` | `audio_ducking_level_v1` | ✅ same | — |
| B12 | Speaker + Bluetooth simultaneous output | `:320` | `multi_output_mode_v1` | ✅ `multi_output_router.dart` | — |
| B13 | DSP snapshot (save/restore chain) | `:331` | `dsp_snapshot_enabled_v1` | ✅ `audio_handler_playback_extras.dart:226` | — |
| B14 | Bluetooth latency calibration (+ manual ms) | `:341`; sheet `bt_latency_tap_sheet.dart` | `setting_bluetooth_latency_offset_ms` | ✅ `SettingsState.audibleLatencyOffset` → lyrics/karaoke sync (`lyrics_view.dart:955`) | — |
| B15 | One-tap quality presets (Maximum fidelity / Smooth / Poor network) | `playback_section.dart:740-800` | writes several keys | ✅ `applyMaximumQualityPreset` etc. — best-in-class on-device shortcut | — |
| B16 | Sleep timer | `:168-176` → `SleepTimerSheet` | `sleep_timer_target` | ✅ `SleepTimerManager` (fade then pause) | — |

### 2.6 Lyrics

| ID | Option | Where surfaced | Storage key | Applied? (trace) | Flag |
|---|---|---|---|---|---|
| Y1 | Per-track lyrics offset (±100 ms chip) | Inline in Now Playing lyrics `lyrics_view.dart:631-720` | `lyrics_offset_v1_<path>` + index | ✅ load on song change `:208-217`, persist `:274-280`, clear at 0 | — |
| Y2 | Lyrics translation (off / translated / bilingual) | Inline header action `lyrics_view.dart:534-580` | none — `_translationMode` is widget state | ⚠ Works, but resets whenever the lyrics view is rebuilt/reopened | **(b)** |
| Y3 | Lyrics typography / alignment / translation default / "hide when instrumental" | — | — | ❌ Absent; sizes are fixed tokens (`lyrics_view.dart:789-818`) | **(p)** |

### 2.7 Online, downloads & system surfaces

| ID | Option | Where surfaced | Storage key | Applied? (trace) | Flag |
|---|---|---|---|---|---|
| D1 | Streaming quality | Network → nav tile `online_section.dart:96-110` | `setting_streaming_quality` | ✅ streaming resolver | — |
| D2 | Download quality (global default) | `online_section.dart:112-124` | `setting_download_quality` | ✅ `yt_download_service.dart:497-499` reads the key directly | — |
| D3 | Per-download quality with size estimate | YTM download button `ytm_download_button.dart:74` | one-shot (`pendingDownloadQuality`) | ✅ `download_repository_impl.dart:1324` | ⚠ does not update D2 (by design, undocumented) |
| D4 | Download concurrency 1–5 | `online_section.dart:126` → `download_settings_tiles.dart:17-100` | `DownloadSettings` own store | ✅ `DownloadRepositoryImpl` reads on admission | ⚠ parallel store |
| D5 | Download location | `online_section.dart:128` | — | ❌ Deliberately disabled tile (`download_settings_tiles.dart:128-160`) — honest limitation | — |
| D6 | Offline-only mode | `online_section.dart:64` | `setting_offline_only_mode` | ✅ gates network UI; hides account rows | — |
| D7 | Wi-Fi-only downloads | `online_section.dart:73` | `setting_wifi_only_mode` | ✅ download admission | — |
| S1 | Lock-screen options (artwork, actions, blur) | — | — | ❌ Absent. The only lock-screen-adjacent control is G13 (keep notification) | **(p)** |
| S2 | Home-screen widget style / which widget / theme | — | — | ❌ Absent. `WidgetService` exists (`features/widgets/widget_service.dart`) and is DI-wired, but no settings surface exposes it | **(p)** |
| S3 | Media notification channel language | implicit via A16 | reads `setting_language_code` | ⚠ `audio_handler.dart:140-142` | **(c)** see F3 |

### 2.8 Settings infrastructure (options about the options)

| ID | Option | Where surfaced | Storage key | Applied? (trace) | Flag |
|---|---|---|---|---|---|
| I1 | Experience mode: Normal / Professional | Sound → card `settings_category_widgets_section.dart:20-30`; also About → explainer | `setting_experience_mode` | ✅ gates DSP/profiles/automation and `_studioControlCounts` footers (`category_metadata.dart:14-19`) | — |
| I2 | Settings search with synonyms | Header `settings_header_section.dart` → `search_results_section.dart` (≈90 hand-written `_SearchItem`s) | — | ⚠ Works well (keywords incl. 'vinyl', 'amoled', 'miniplayer'), but it is a **hand-maintained duplicate** of the UI: `dock`, `radius` are not indexed, and `studio` routes to Experience Mode (`:1084`) | **(c)** + drift risk |
| I3 | Category rail (7 categories) | `category_metadata.dart:3-11` | — | ✅ phone segmented/dashboard + tablet master-detail | — |
| I4 | Tablet sidebar expanded/collapsed | Gesture on shell rail | `sidebar_extended_<deviceClass>` | ✅ `app_shell.dart:100,456` | ⚠ no Settings entry (implicit layout memory) |
| I5 | Tablet inspector width | Drag gesture on inspector | `tablet_inspector_width_<deviceClass>` | ✅ `tablet_side_inspector.dart:168,408` | ⚠ same |

**Inventory count: 87 distinct options** (A1–A18, P1–P12, G1–G14, L1–L9, B1–B16, Y1–Y3, D1–D7, S1–S3, I1–I5). By the Applied column: **66 ✅ fully applied**, **12 ⚠ applied with a caveat**, **9 ❌ absent**. By flag: **0 (a)**, **2 (b)**, **10 (c)**, **5 (d)**, **8 (p)**.

**On (a) = 0, deliberately:** no *user-facing* toggle is stored-but-never-read. Every `PrefsKeys` constant that has a control also has a consumer. The one dead key found is not a toggle — it is a key that **backup writes and nothing reads** (`'setting_bit_perfect'`), covered in F8. That distinction matters: the flag taxonomy's most alarming category is genuinely empty here, while the corruption risk has simply moved into backup.

---

## 3. Flag findings, consolidated

Each finding is stated with the exact reader/writer so it can be checked without re-deriving.

### F1 — Theme Studio is unreachable from the place users configure themes · *verified*
`/theme-studio` is registered at `app_router.dart:843` and pushed from exactly one site: `home_screen.dart:625`, inside the Home "Browse more tools" sheet. The Settings→Look section ends its theme rows at Player Theme / Slider / Button / Visualizer / Color source / Dock (`appearance_section.dart:195-270`) with no Studio entry. Settings search cannot compensate: `search_results_section.dart` has no `radius` or `studio theme` item, and `'studio'` is a keyword of **Experience Mode** (`:1084`), so typing "studio" teaches the user the wrong thing.
Impact: the app's most distinctive customization surface is effectively undiscoverable.

### F2 — Studio radius/glow are conditionally inert while the preview pretends otherwise · *verified*
`resolveCustomRadius` returns the user's radius **only** when `themeColorSource == ThemeColorSource.custom` (`player_shape.dart:13-20`); the chrome repeats the same gate inline (`player_theme_chrome.dart:576-578, 766-773`). The Studio's preview card rounds with the local `_cornerRadius` unconditionally (`custom_theme_builder_screen.dart:338, 388`), and `onChangeEnd` persists the value (`:529-531`) without touching the source. A user who drags radius first, without tapping a palette swatch, sees a rounded preview and no change in the player.

### F3 — Language "System" leaks into the media notification as a literal code · *verified*
`setLanguage` persists the string `system` (`settings_cubit.dart:1519-1524`); `MaterialApp` treats it as "follow OS" (`main.dart:1404-1406`). `PulsrAudioHandler` instead does `prefs.getString(PrefsKeys.languageCode) ?? prefs.getString('setting_language') ?? Platform.localeName…` (`audio_handler.dart:140-142`). Because `languageCode` is non-null once the user has picked *System*, the `Platform.localeName` fallback is unreachable and the notification channel stays English on an Arabic/Spanish device. (The `setting_language` key is a legacy read-only fallback — `player_prefs.dart:17` — not a second writer.)

### F4 — "Button Style" reaches chips, not buttons · *verified*
`PulsrCapsuleStyle.resolveRadius` is applied at 9 sites: `pulsr_chip.dart:96`, `pulsr_section_header.dart:168,182`, `discovery_chip.dart:33`, `quran_radio_hero_carousel.dart:649,1478`, `lyrics_view.dart:1019`, `queue_slot_switcher.dart:33`. Material buttons are themed with a fixed `AppRadii.buttonRadius` = 14 dp (`app_radii.dart:6`), applied in `aura_theme.dart:1002-1010` filled, `:1018-1030` elevated, `:1038-1060` outlined. Choosing "Capsule" therefore changes filter chips while every dialog's primary button stays 14 dp-rounded.

### F5 — High contrast forces dark system chrome, even in the light HC theme · *verified*
`highContrastThemeFor(Brightness.light)` builds a genuine light theme (`aura_theme.dart:312-320`), but `main.dart:1354-1357` computes `isDarkTheme = isHighContrast || …`, and that value drives `statusBarIconBrightness` / `systemNavigationBarIconBrightness` (`main.dart:1364-1369`). Light + high contrast therefore paints light status-bar icons over a light app. *Visual result unverified on device; the logic is certain.*

### F6 — Reduce Motion silently becomes "calm density" and kills shaders · *verified*
`setReduceMotion` calls `GpuBudget.setEnabled(value)` (`settings_accessibility_ext.dart:18-27`). Seven surfaces then compute `isCalm = p.isCalmDensity || GpuBudget.isEnabled` (`bottom_nav_bar.dart:157`, `stacked_bottom_dock.dart:549`, `mini_player.dart:455`, `hero_mix_card.dart:33`, `quick_card.dart:29`, `settings_hero_card.dart:28`), and the visualizer downgrades itself (`audio_visualizer.dart:568`). So A11 and A9 (calm) are two controls for one visual outcome, and turning on an accessibility toggle removes the Milkdrop/GPU presentation with no mention in the subtitle.

### F7 — Settings state lives in five different persistence channels · *verified*
1. `SettingsCubit` + `SharedPreferences` (most options).
2. `DockStyleController` — a static `ValueNotifier` writing `PrefsKeys.dockStackMode` directly (`dock_style_controller.dart:17-47`), invisible to `SettingsState` and to cloud/backup.
3. `SoundFeedbackService.enabledNotifier` (A13).
4. `DownloadSettings` model with its own `save()` (D4).
5. Widget-local `SharedPreferences` in nine presentation files (`headset_controls_section.dart`, `playback_section.dart:556-627`, `scrobbler_settings_modal.dart`, `smart_audio_section.dart`, `theme_schedule_row.dart`, `audio_sound_dop_selector.dart`, `headphone_safety_sheet.dart`, `scrobble_stats_screen.dart`, `settings_screen_controller.dart`).
Consequence: no single "appearance state" object, no uniform reset, and backup coverage is whatever the author remembered (F8).

### F8 — Backup/restore drops most appearance options and writes an orphan key · *verified*
`ExportBackupUseCase` (`backup_usecases.dart:104-130`) exports theme mode, accent, source, player theme, slider, button, visualizer, RG, quality, EQ. It omits: language, high contrast, dim white point, reduce motion, haptics, glass intensity, visual density, Studio radius/glow, all four gesture mappings, dock style, canvas flags, waveform toggle, theme schedule, headset config. It also writes `'bitPerfectMode': prefs.getBool('setting_bit_perfect')` (`:123`) — a key no reader uses; the live key is `PrefsKeys.bitPerfectOutput = 'setting_bit_perfect_output'` (`prefs_keys.dart:73`). Import writes the same orphan back (`:780`). Net effect: restoring a backup can silently leave bit-perfect *off* while reporting settings restored; and it defaults several values that differ from the live defaults (`playerSliderStyle` → `normal` at `:110` vs state default `capsule` at `settings_state.dart:118`; `visualizerStyle` → `bar` at `:113` vs state default `off` at `:120`).

### F9 — Visualizer style is global but only 8 of 11 themes render it · *verified*
`visualizerStyle` is read by Classic (`parts/classic_player_theme_build.dart:14-35,150-168`), Card (`parts/card_player_theme_build.dart:14-39`), Circle (`parts/circle_player_theme_build.dart:8-54`), CD (`parts/cd_player_theme_build.dart:7-53`), Cassette (`parts/cassette_player_theme_build.dart:8-73`), Clean (`clean_player_theme.dart:191-205`), Waveform (`painters/waveform_stage.dart:72-81`), Milkdrop (`milkdrop_player_theme.dart:50-85`). `vinyl_player_theme.dart` and `minimal_player_theme.dart` contain no `AudioVisualizer` reference; Karaoke is a lyrics surface. The picker gives no hint that the choice is theme-dependent.

### F10 — Mini player reflects only the vinyl theme, and degrades when swipe mapping changes · *verified*
`mini_player.dart:777-780` swaps artwork for `SpinningVinylDisc` only when `playerThemeMode == vinyl`; no other theme influences the mini player. The queue carousel is enabled only when left=Next and right=Previous (`:421-424`), so choosing Volume/None silently removes a navigation affordance the user may not connect to that setting.

### F11 — "Dynamic theming" is a second key for the accent source · *verified (duplicate)*
`setThemeColorSource` writes both the enum key and `setting_dynamic_theme = (source == artwork)` (`settings_cubit.dart:1398-1404`); load reads the enum first and only falls back to the bool (`:398-407`). Any legacy/backup writer of the bool is silently ignored while the enum exists. The prefs file itself documents this history (`prefs_keys.dart:36-41`).

### F12 — Search is a hand-maintained mirror of the UI and already lags · *verified*
`search_results_section.dart` lists ~90 items with synonyms; `dock` and `radius` return zero matches, and `glass` only matches the Look *category* card (`:512-527`), not the intensity slider. Since new settings are added to section widgets, not to the search list, the index will keep drifting. (Positive: the synonym work is genuinely better than most apps — `'vinyl'`, `'amoled'`, `'miniplayer'`, `'waveseek'`-style terms are present.)

### F13 — Two playback surfaces duplicate the same tiles · *verified (maintenance)*
`PlaybackSection` branches into `_buildNormal` (`playback_section.dart:53-160`) and `_buildProfessional` (`:162-345`), which repeat gapless/resume/waveform/crossfade with slightly different copy and conflict wiring. Every future playback option must be added twice, and the two already differ (professional adds presets/automix/ducking).

### F14 — No in-app text scaling, and the OS range is clamped · *verified (coverage)*
`main.dart:1392-1399` clamps 0.8–2.0. Nothing in `lib/features/settings` exposes a scale. Users who want "bigger lyrics" or "denser library" have one OS lever that also scales every chrome element.

---

## 4. Score table

Rubric applied as given: 0–5 broken/absent, 6 adequate, 7 solid production, 8 strong, 9 best-in-class, 10 reference-grade.

| Dimension | Score | Evidence (one line each) |
|---|:--:|---|
| **Option coverage** | **7 / 10** | 87 inventoried options incl. 11 themes, 3 accent sources, 4 dock styles, full gesture remap, per-track lyric offset, headset remap, visualizer presets. Missing: list density, text scale, mini-player style, lyrics typography, lock screen, widget, per-theme tuning (`grep` yields no `listDensity`, `miniPlayerStyle`, `textScaleSetting`). |
| **Option wiring** | **6 / 10** | Theme/mode/accent/contrast/motion/gestures/dock are genuinely read (`main.dart:1276-1406`, `player_gesture_scope.dart:29-64`, `app_shell.dart:398-404`). But F2 (radius inert), F4 (button style), F8 (backup orphan + omissions), F9 (8/11 themes) and F3 (notification language) mean several controls do not do what they say. |
| **Discoverability** | **6 / 10** | Strong category rail + synonym search + Experience-mode bridge footers (`studio_bridge_footer.dart`, `_studioControlCounts`). Undermined by F1 (Studio only via Home), F12 (dock/radius unindexed, `studio` misroutes), and no Lyrics/Player/Downloads category (`category_metadata.dart:3-11`). |
| **Consistency of settings UI** | **5 / 10** | Five persistence channels (F7), duplicated playback bodies (F13), hand-maintained search (F12), hard-coded English rows ('UI Sound Effects' `appearance_section.dart:390`, 'Spotify Canvas' `:401`, 'Discord Rich Presence' `online_section.dart:180-190`) beside fully localized ones, and a mixed disable/hide policy (D5 disabled tile vs A8 silently ignored). |
| **Preview & feedback** | **7 / 10** | Theme picker renders **live** theme previews per row and in a carousel (`settings_theme_pickers.dart:376-560`); Studio has a live player preview and per-theme chips (`custom_theme_builder_screen.dart:300-375`); sliders show values; conflict cards explain disabled states (`settings_conflict_card.dart`). Missing: A/B compare, visualizer preview (icon-only), mini-player preview, and any preview that reflects the *actual* applied radius (F2). |

**Overall: 6.2 / 10** — a broad, mostly-real option surface held back by four honesty defects (F1, F2, F4, F8) and a fragmented settings architecture (F7).

---

## 5. Benchmark gap list — Apple Music, Spotify, Poweramp, Plexamp, YouTube Music

Method note: competitor capabilities below are stated as *expected customization*, not as audited builds. Only the Poweramp row has on-run evidence (a forum search snippet; the page itself was not fetched). Rows marked ⌁ are product-knowledge expectations and were **not verified this run** — treat them as hypotheses to confirm before building.

| Expected customization | Who ships it | Why it matters for Pulsr specifically | Status in Pulsr |
|---|---|---|---|
| **Per-theme accent + per-theme geometry** (each skin owns its palette/radius, not one global accent) | Poweramp: each skin exposes its own options incl. seek-bar style (`Settings → Look and Feel → Skin → Seekbar Style`, [forum snippet](https://forum.powerampapp.com/topic/29964-poweramp-builds-1002-1025)) ⌁ | Pulsr has 11 themes but **one** accent and **one** radius gate. A user who loves Vinyl cannot tune it; switching themes changes the whole visual system | ❌ Missing (radius/glow exist but are gated, F2) |
| **Corner-radius / shape control that applies app-wide** | Poweramp skins ⌁; Plexamp theme variants ⌁ | Pulsr offers 0–48 dp but only for player chrome and only with `source=custom`. Cards, sheets, dialogs, tiles stay fixed (`AppRadii.cardRadius`/`buttonRadius` are `const`) | ⚠ Partial (player chrome only) |
| **Cover-art-derived palette toggle that is per-surface and instant** | Plexamp (album-art key extraction) ⌁; Spotify palette ⌁ | Pulsr's artwork palette runs through a 500 ms debounce + 5 s timeout + LRU palette cache (`dynamic_theme_cubit.dart:150-320`); fine, but it recolours the whole app, with no "only Now Playing" scope | ⚠ Exists, no scope control |
| **List density / compact library mode** | Poweramp list options ⌁ | With an 818-file, 323 k-LOC-scale library UI, density is the highest-value missing display option; Pulsr hard-codes compact in a few tabs | ❌ Missing (L8) |
| **Font choice / lyric typography** | Poweramp font settings ⌁; Apple Music lyric size follows system ⌁ | Pulsr is Manrope-only (`aura_theme.dart:13`) and lyrics sizes are fixed tokens; karaoke users cannot enlarge text without scaling the entire UI | ❌ Missing (Y3, A17) |
| **Mini-player style variants** | Apple Music (compact bar + expanded), Poweramp (multiple skins), Spotify (bar vs full) ⌁ | Pulsr's mini player is one layout + one theme reaction (vinyl only, F10); dock style changes stacking, not the player itself | ❌ Missing (G3) |
| **Gesture remap beyond defaults** | Poweramp (swipe/double-tap remap) ⌁ | **Pulsr already leads here** (G1/G2/G4/G5). Worth protecting in any redesign | ✅ Strength |
| **A/B theme preview / hold-to-compare** | Not standard in any of the five ⌁ | Pulsr's live previews make A/B cheap to add; currently the picker *applies* on page change (`settings_theme_pickers.dart:441-446`), so "browsing" mutates the setting | ❌ Missing |
| **Crossfade visualization** (see the blend region on the seek bar) | Poweramp visualizes crossfade ⌁ | Crossfade is a headline audiophile feature (B2/B3) but the UI gives no feedback that a blend is active or how long it is | ❌ Missing |
| **Lock-screen presentation controls** (artwork on/off, action set) | Apple Music/iOS lock-screen artwork ⌁; Poweramp lock-screen options ⌁ | Pulsr's only lock-screen-adjacent toggle is "keep notification on pause", which needs a restart (G13) | ❌ Missing (S1) |
| **Home-screen widget variety / configuration** | Poweramp widgets ⌁; YouTube Music widget ⌁ | `WidgetService` already pushes title/artist/queue to a widget (`widget_service.dart:253-280`) with **zero** user configuration | ❌ Missing (S2) |
| **In-app text size** | Poweramp ⌁; Apple Music inherits OS ⌁ | Pulsr clamps OS scale to 2.0 and offers nothing in-app; accessibility gap | ❌ Missing (A17) |
| **Compact "simple mode" that hides advanced surface** | YouTube Music (minimal by design) ⌁ | **Pulsr already leads**: Experience Mode Normal/Professional with counted hidden controls (I1) | ✅ Strength |
| **Import/export of a full theme (share a look)** | Poweramp skin files ⌁ | Pulsr has JSON export/import (P6) but a single slot with no naming/library | ⚠ Partial |

Filtered out as *not* worth building for real user value (mentioned so the omission is deliberate): reorderable settings tabs, custom app icons, per-album accent persistence, animated theme transitions between themes, and a colour-blind simulator. They add surface without changing daily use.

---

## 6. Top gaps (max 8, ranked by user-visible value per unit of work)

1. **Theme Studio is effectively hidden and half-inert** (F1 + F2). The best customization feature in the app is two taps deep in Home and its shape controls silently depend on a different setting.
2. **"Button Style" does not style buttons** (F4). A one-word fix in the theme (or an honest rename) closes a credibility gap that touches every dialog.
3. **No list density for the library** (L8). The single most requested-class display option for a large local library, and currently hard-coded per tab.
4. **No mini-player options beyond swipes** (G3, F10). The mini player is the most-seen surface in the app; it has one layout and reacts to one of eleven themes.
5. **No lyrics options hub** (Y3/Y2). Pulsr markets karaoke/lyrics heavily (11th theme is lyrics-first) yet exposes no font size, alignment, translation default, and drops the translation choice on rebuild.
6. **Settings integrity: backup drops ~20 appearance keys and writes an orphan bit-perfect key** (F8). Silent data loss on device migration is worse than a missing option.
7. **No lock-screen or widget customization** (S1/S2) while both subsystems exist. Users see a fixed notification and a fixed widget in a player that otherwise lets them tune everything.
8. **No in-app text scale; light+high-contrast breaks status-bar icons** (A17, F5). Accessibility options should not make text harder to read.

---

## 7. Path to 10/10

### P0 — correctness & honesty (do before adding options)

**P0.1 — Make Studio shape controls honest.**
*Files:* `lib/features/player/presentation/themes/custom_theme_builder_screen.dart:529-531`; `lib/features/settings/cubit/settings_cubit.dart:1547-1560`; `lib/features/player/presentation/themes/player_shape.dart:13-32`.
*Change:* in `setCustomThemeRadius` / `setCustomThemeGlow`, emit `themeColorSource: ThemeColorSource.custom` and persist `setting_theme_color_source` alongside the value (matching what `setCustomAccentColor` already does at `:1526-1545`). Alternatively disable both controls with an inline hint when source ≠ custom.
*Acceptance:* with accent source = Artwork, dragging radius to 40 changes Now Playing chrome corner radius within one frame and survives restart; a widget test asserts that after `setCustomThemeRadius(40)` the chrome resolves 40 even though the previous source was `artwork` (the setter promotes the source to custom).

**P0.2 — Surface Theme Studio in Settings and in search.**
*Files:* `lib/features/settings/presentation/sections/appearance_section.dart` (insert a nav tile after the Player Theme tile at `:195`); `lib/features/settings/presentation/sections/search_results_section.dart` (new `_SearchItem` + keywords `radius`, `glow`, `theme studio`; disambiguate the existing `'studio'` keyword at `:1084`).
*Change:* add `_navTile(Icons.palette_rounded, l10n.themeStudio, l10n.themeStudioSubtitle, onTap: () => context.push('/theme-studio'))`; add a search item that pushes the route.
*Acceptance:* Settings → Look shows "Theme Studio"; searching `radius`, `glow` or `theme studio` returns it first; searching `studio` returns both Theme Studio and Experience Mode with distinct titles; a golden/widget test covers the new tile.

**P0.3 — Make Button Style govern real buttons (or rename it).**
*Files:* `lib/core/theme/aura_theme.dart:1002-1060`; `lib/main.dart:1310-1340` (theme construction); `lib/core/theme/pulsr_button_style.dart:33-45`.
*Change:* pass `AppButtonStyle` into `AuraTheme.customTheme` (or read it from `SettingsCubit` in `main.dart` and thread it), and resolve filled/elevated/outlined/`segmentedButtonTheme` shapes via `PulsrCapsuleStyle.resolveRadius`.
*Acceptance:* with Capsule selected, `FilledButton` in Settings and in a dialog renders fully rounded (radius ≥ height/2); with Classic, 14 dp; golden test on one dialog + one settings CTA.

**P0.4 — Fix backup/restore coverage and the orphan bit-perfect key.**
*Files:* `lib/data/usecases/backup_usecases.dart:104-130` (export) and `:730-800` (import).
*Change:* replace string literals with `PrefsKeys.*`; add every appearance key from §2 (`languageCode`, `highContrast`, `dimWhitePoint`, `reduceMotion`, `hapticsEnabled`, `liquidGlassTint`, `visualDensityMode`, `customThemeRadius`, `customThemeGlow`, gestures ×4, `dockStackMode`, `canvasEnabled`, `canvasAsBackdrop`, `waveformSeekBar`, `autoThemeByTime` + schedule start/end); replace `'setting_bit_perfect'` with `PrefsKeys.bitPerfectOutput`; align written defaults with `SettingsState` defaults.
*Acceptance:* an integration test exports, mutates all keys, imports, and asserts each key equals the exported value (including bit-perfect true); no key written by import lacks a reader.

**P0.5 — Fix light + high-contrast system chrome.**
*File:* `lib/main.dart:1354-1369`.
*Change:* compute chrome brightness from the resolved theme (`Theme.of(context).brightness` after `themeMode` resolution), not from `isHighContrast`.
*Acceptance:* High contrast + Light yields dark status-bar icons; High contrast + AMOLED yields light icons; a widget test asserts the `AnnotatedRegion` value for both combinations.

### P1 — coverage that users will feel

**P1.1 — Mini-player style presets.**
*Files:* `lib/features/settings/cubit/settings_state.dart` (+ `MiniPlayerStyle {standard, compact, artwork}` field), `lib/features/settings/cubit/settings_cubit.dart`, `lib/features/player/presentation/mini_player.dart`, `lib/features/settings/presentation/sections/appearance_section.dart`.
*Change:* three layouts driven by one enum: standard (today), compact (no artwork, 56 dp), artwork-forward (96 dp art, title/artist overlay, progress hairline). Read `playerThemeMode` for a per-theme hint (CD/Cassette could use their asset).
*Acceptance:* switching presets changes height and content without restart; all three respect text scale 2.0 without overflow at 360×800; persisted and included in backup (P0.4 list).

**P1.2 — Lyrics settings section.**
*Files:* new `lib/features/settings/presentation/widgets/lyrics_section.dart`; wire from `settings_category_widgets_section.dart` under `look`; consume in `lib/features/player/presentation/widgets/lyrics_view.dart:789-818`.
*Change:* four options — font scale 0.8–1.6, alignment (start/center), "translate by default", "default offset" applied when a track has no stored offset.
*Acceptance:* font scale changes lyric text live and persists; default translation applies on first open (replacing the ephemeral `_translationMode`, Y2); default offset applies only when `LyricsOffsetStore` has no entry for the path.

**P1.3 — Library list density.**
*Files:* `lib/features/settings/presentation/sections/library_section.dart`; `lib/features/library/presentation/tabs/library_songs_tab.dart:150-170`; `lib/core/widgets/song_tile.dart`.
*Change:* `comfortable | compact | artwork-only`; compact reduces row height and hides the secondary line; artwork-only hides text.
*Acceptance:* compact fits ≥30 % more rows in the same viewport at 360×800; artwork-only renders without text nodes in the semantics tree; preference persists and is searchable.

**P1.4 — In-app UI scale.**
*Files:* `lib/main.dart:1392-1399`; `lib/features/settings/presentation/sections/appearance_section.dart`.
*Change:* multiply the OS scaler by a user factor (0.85–1.30) inside the existing `MediaQuery` builder, clamped with the current 0.8–2.0 window; expose as a slider with a live sample.
*Acceptance:* Settings itself does not clip at 1.30; lyrics and song tiles scale; the OS max still wins when larger.

### P2 — polish & architecture

**P2.1 — Previews that tell the truth.** Visualizer picker gains an animated preview tile; the theme picker gains hold-to-compare (A/B) instead of applying on page change (`settings_theme_pickers.dart:441-446`); the Studio preview must render the *gated* radius so it matches the player.
*Acceptance:* press-and-hold on a theme previews without persisting; releasing outside cancels; visualizer tiles animate at ≥30 fps with `GpuBudget` off.

**P2.2 — One settings registry.** New `lib/features/settings/settings_registry.dart` describing each option (key, type, default, section, label, search keywords, backup group); generate the search list and the backup map from it.
*Acceptance:* adding an option in one place makes it searchable and backed up with no second edit; a ratchet test fails if a `PrefsKeys` constant has no registry entry.

**P2.3 — Lock screen & widget options.** Expose `WidgetService` configuration (which widget: now-playing vs queue; theme: follow app / monochrome) and a lock-screen "show artwork" preference bridged to the native notification.
*Acceptance:* changing widget theme relabels the home widget within one update cycle; lock-screen artwork toggle changes the notification large icon without a restart.

**P2.4 — Crossfade visualization.** Draw the blend window on the seek bar when `crossfadeSeconds > 0`, and show the BPM-sync state when B3 is on.
*Acceptance:* with 4 s crossfade, the last 4 s of the bar renders a distinct blend band; the band disappears at 0 s; no layout shift.

---

## 8. Verification log / limits

- **Read in full:** `settings_screen.dart`, `settings_state.dart`, `settings_cubit.dart` (key map + load + setters), and the presentation sections that own options: `appearance_section.dart`, `gestures_section.dart`, `library_section.dart`, `online_section.dart`, `tablet_layout_section.dart`, `phone_layout_section.dart`, `category_metadata.dart`, `settings_category_widgets_section.dart`; plus `settings_theme_pickers.dart` (relevant spans), `custom_theme_builder_screen.dart`, `theme_registry.dart`, `player_shape.dart`, `mini_player.dart` (gesture + theme spans), `player_gesture_scope.dart`, `glass_container.dart`, `dynamic_theme_cubit.dart`, `prefs_keys.dart`, `main.dart:1230-1420`, `aura_theme.dart` (theme construction + button themes), `headset_controls_section.dart`, `download_settings_tiles.dart`, `backup_usecases.dart:60-150, 730-800`. Remaining widget files were checked by targeted grep, not line-by-line.
- **Greps used as proof:** `visualizerStyle` consumers (8 themes), `isGlassButtons|buttonRadius(` (9 sites), `GlassContainer|BackdropFilter` (10/6 refs), `miniPlayerSwipeLeft|nowPlayingDoubleTap` (read sites), `listDensity|miniPlayerStyle|MiniPlayerStyle` (0 hits), `tabletInspectorWidthKey|sidebarExtendedKey` (shell only), `PrefsKeys.*` set/get symmetry (discarded as unreliable for DSP keys because `EqualizerManager` persists via map keys — see `equalizer_manager.dart:540,574`).
- **Not verified (would need a running app):** visual result of light+high-contrast chrome (F5); actual frame impact of glass/visualizer; whether the theme picker's live previews stay in sync at 2.0 text scale; RTL rendering of the new Studio and dock sheets in Arabic.
- **Corrections to the brief's premise, for the record:** (1) "text scale/density" is only *partly* present — density exists as Comfortable/Calm (chrome intensity), there is no text-size control; (2) "artwork source" as a cover-art priority setting does not exist — what exists is accent *colour* source; (3) "nav dock style" exists and is persisted, but lives outside `SettingsState`; (4) "lock-screen/home-widget options" do not exist at all despite both subsystems being implemented.
- **Competitor evidence:** one on-run source (Poweramp forum snippet, page not fetched). All other competitor rows are marked ⌁ and should be confirmed against vendor docs before being used to justify roadmap work.
