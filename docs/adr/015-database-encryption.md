# ADR 015: Database Encryption at Rest (SQLCipher)

## Status
Proposed — documented decision, not yet implemented.

## Context
`lib/data/db/app_database.dart` opens the library SQLite database without a
key. The `onConfigure` hook sets `foreign_keys`, `journal_mode = WAL`,
`synchronous = NORMAL` and `case_sensitive_like`, but there is no
`PRAGMA key`/SQLCipher. As a result the database file is plaintext: it exposes
the full local library (file paths, titles, artists), play history, favorites,
and playlist membership to anyone with filesystem access (rooted device, ADB
backup, physical extraction) even though Pulsr is positioned as privacy-first.

The gap register and the 2026-10 audio/privacy audits both flag this
(`gaps.md`). This ADR records the decision and the migration plan.

## Decision
Treat encryption at rest as a **roadmap item**, evaluated against the following
options, rather than silently shipping plaintext:

1. **SQLCipher via `drift` + `sqlcipher_flutter_libs`** (preferred long-term).
   Pass a key through `NativeDatabase`'s `setup`, migrate the existing plaintext
   file with `sqlcipher_export`, and store the key in `flutter_secure_storage`.
2. **Android `EncryptedFile`/Keystore wrapper** on the DB file (Android-only).
3. **Status quo**, explicitly documented, until key-management and cross-platform
   (iOS/macOS/desktop) parity is decided.

## Consequences
### Why not implemented now
- **Destructive migration**: encrypting an existing DB requires a one-shot
  re-key of every user's database. A failure mid-migration loses the library.
  This needs a tested, resumable migration and a backup-before-migrate step.
- **Key management**: the key must itself be protected (Keystore/Keychain) and
  must not be lost; losing it bricks the library. Secure-storage availability
  already has failure paths (see the proxy-password handling in
  `settings_proxy_actions.dart`) that must be hardened first.
- **Build/compatibility cost**: `sqlcipher_flutter_libs` adds native binaries
  per platform and can conflict with the existing native DSP/JNI build; a
  physical-device test matrix is required before shipping.

### Positive (once done)
- Library metadata, history and playlists become unreadable without the key.
- Aligns the storage layer with the app's privacy claims.

### Negative / Trade-offs
- CPU/WAL overhead and a larger binary.
- Non-trivial upgrade path; users on old versions need the migration to run
  exactly once and be crash-safe.

## Follow-up
- Prototype the SQLCipher migration behind a feature flag on 2–3 physical
  devices, including a kill-during-migration recovery test.
- Add a schema/health assertion that the DB is encrypted when the feature flag
  is on.
- Document the key-recovery story (what happens if secure storage is wiped).
