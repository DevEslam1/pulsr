# Pulsr Documentation Index

This directory mixes **living references** and **date-stamped audit snapshots**. Use the label to decide whether a document is current guidance or historical evidence.

**Last reviewed:** 2026-11-17.

---

## Start here

| Document | What it is | Status |
|---|---|---|
| [`../README.md`](../README.md) | Product overview, feature summary, build guide and permissions | Living |
| [`FEATURE_MATRIX.md`](FEATURE_MATRIX.md) | Source-verified capability list, counts and explicit limitations | Living — update when shipping features |
| [`../DESIGN.md`](../DESIGN.md) | Design system: tokens, motion, components and accessibility rules | Living |
| [`../DESIGN_SYSTEM.md`](../DESIGN_SYSTEM.md) | Palette, typography, player chrome and theme inventory | Living |
| [`../RUNBOOK.md`](../RUNBOOK.md) | YTM tap-to-sound latency runbook and verification gates | Living |
| [`../CHANGELOG.md`](../CHANGELOG.md) | Hardening and delivery changelog, including documentation refreshes | Living |
| [`../website/`](../website/) | Landing page (`index.html`, `styles.css`, `app.js`) | Living |

---

## Architecture and player

| Document | What it covers | Status |
|---|---|---|
| [`player_architecture.md`](player_architecture.md) | Volume authority, interruption manager and hardened player architecture | Current design |
| [`adr/`](adr/) | 16 Architecture Decision Records (001–015, two 007s) | Current decisions; supersede individually when changed |
| [`NATIVE_AUDIO_MATRIX.md`](NATIVE_AUDIO_MATRIX.md) | Native host test matrix: DSD512, channel manager, limiter, DoP | Current snapshot (2026-10-27) |
| [`gaps/README.md`](gaps/README.md) | Gap-closure status versus USB Audio Player PRO, with verification log | Current status (2026-11-16) |
| [`qa/dsp-device-validation.md`](qa/dsp-device-validation.md) | Manual device checklist for EQ, DSP, routing, USB and Quran Mode | Current checklist |
| [`../CLAUDE.md`](../CLAUDE.md) | Codebase/architecture guide for AI agents | Living; keep in sync when structure changes |
| [`../pulsr-context.md`](../pulsr-context.md) | Generated context snapshot for AI tooling | Generated; do not treat as canonical |
| [`../gaps.md`](../gaps.md) | Historical gap analysis | Historical; do not treat as current status |

---

## Dated audits and verification records

These are snapshots of a specific date. They intentionally document defects, limits and hardware gaps that may have moved since. Do not edit them to look current; add a newer record instead.

| Document | Date | Scope |
|---|---|---|
| [`AUDIO_BRIDGE_VERIFICATION.md`](AUDIO_BRIDGE_VERIFICATION.md) | 2026-10-03 | Bit-perfect and native bridge verification |
| [`AUDIO_DSP_REVIEW_2026-10-03.md`](AUDIO_DSP_REVIEW_2026-10-03.md) | 2026-10-03 | DSP, JNI and Android bridge review |
| [`AUDIO_DSP_HARDENING_2026-10-03.md`](AUDIO_DSP_HARDENING_2026-10-03.md) | 2026-10-03 | DSP hardening and playback startup repair |
| [`AUDIO_OUTPUT_SHEET_AUDIT_2026-10-04.md`](AUDIO_OUTPUT_SHEET_AUDIT_2026-10-04.md) | 2026-10-04 | Output routing and reporting audit |
| [`QURAN_BLUETOOTH_DEVICE_CHECK_2026-10-04.md`](QURAN_BLUETOOTH_DEVICE_CHECK_2026-10-04.md) | 2026-10-04 | Quran Mode on Bluetooth and USB |
| [`MAX_RATE_FEATURE_DOSSIER_2026-10-26.md`](MAX_RATE_FEATURE_DOSSIER_2026-10-26.md) | 2026-10-26 | 37-feature scorecard and execution tranche |
| [`YTM_STACK_REVIEW_2026-10-27.md`](YTM_STACK_REVIEW_2026-10-27.md) | 2026-10-27 | InnerTube, NewPipe and PoToken review |
| [`YTM_AGE_GATE_FIX_2026-10-30.md`](YTM_AGE_GATE_FIX_2026-10-30.md) | 2026-10-30 | Age-restricted track failure and fix |
| [`SOUND_QUALITY_AUDIT_2026-11-09.md`](SOUND_QUALITY_AUDIT_2026-11-09.md) | 2026-11-09 | 16/24/32-bit and bit-perfect audit |
| [`player_architecture_audit.md`](player_architecture_audit.md) | Phase 0 | Pre-refactor player audit |

The scorecard workbook [`pulsr_max_rate_scorecard_2026-10-26.xlsx`](pulsr_max_rate_scorecard_2026-10-26.xlsx) is the sortable companion to the 2026-10-26 dossier.

---

## Gap-closure handoffs

[`gaps/README.md`](gaps/README.md) is the index and status table. Module handoffs:

| Document | Feature | Status in source |
|---|---|---|
| [`gaps/remote-sources.md`](gaps/remote-sources.md) | WebDAV / FTP / SMB sources | Browse + playback done; library scanning partial |
| [`gaps/sacd-codecs.md`](gaps/sacd-codecs.md) | SACD ISO indexing and extraction | Done; other codecs still need native decoders |
| [`gaps/usb-ergonomics.md`](gaps/usb-ergonomics.md) | Per-DAC USB quirks | Partial; quirk editor ships, some sink hooks remain |
| [`gaps/tts-announcements.md`](gaps/tts-announcements.md) | Spoken track announcements | Done; music ducking persisted but not applied |
| [`gaps/dlna-renderer.md`](gaps/dlna-renderer.md) | DLNA/UPnP renderer | Done |
| [`gaps/profiles-diagnostics.md`](gaps/profiles-diagnostics.md) | Audio profiles, diagnostics and safe mode | Done |
| [`gaps/assistant-surface.md`](gaps/assistant-surface.md) | Search suggestions and assistant bridge | Done |
| [`gaps/system-behaviour.md`](gaps/system-behaviour.md) | Audio focus, USB release and volume policy | Partial; see handoff for unwired items |

---

## Conventions

1. **Current vs dated.** A file with a date in its name is a snapshot. Do not rewrite its findings; write a new dated document and link it.
2. **Feature counts.** Use [`FEATURE_MATRIX.md`](FEATURE_MATRIX.md) for counts that appear in the README, website or release notes.
3. **Limitations are part of the feature.** Document unsupported or experimental paths beside the feature, not in a separate marketing claim.
4. **Source wins.** If a document and the code disagree, verify the code path and update the living document; leave the dated audit untouched.
5. **No secrets, paths or account tokens.** Diagnostics and audit examples must stay redacted.

---

## Verification commands

```bash
flutter analyze
flutter test
dart run build_runner build --delete-conflicting-outputs

cd server/pulsr_party && go test ./...
./scripts/run_native_dsp_tests.sh
```

Windows PowerShell equivalents for the Android audio harnesses live in `scripts/run_audio_bridge_smoke.ps1` and `scripts/run_audio_playback_smoke.ps1`.
