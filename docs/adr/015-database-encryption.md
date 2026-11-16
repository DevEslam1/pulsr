# ADR 015: Database Encryption at Rest (SQLCipher / SQLite3MultipleCiphers)

## Status
Accepted — implemented via `package:sqlite3`'s `sqlite3mc` build hook.

## Context
`lib/data/db/app_database.dart` opens the library SQLite database. Without a
key the file is plaintext: it exposes the full local library (file paths,
titles, artists), play history, favourites and playlist membership to anyone
with filesystem access (rooted device, ADB backup, physical extraction) even
though Pulsr is positioned as privacy-first.

The gap register and the 2026-10 audio/privacy audits both flag this
(`gaps.md` P1-13).

## Decision
Encrypt the database at rest with SQLite3MultipleCiphers, selected through the
`package:sqlite3` v3 build hook (no extra dependency):

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

`lib/data/db/database_encryption.dart` owns the lifecycle:

1. **Capability probe** — the selected SQLite build answers `PRAGMA cipher`
   (SQLite3MultipleCiphers) or `PRAGMA cipher_version` (SQLCipher). When no
   cipher is available the app continues plaintext and the health check reports
   `unavailable`; it never crashes or deletes data.
2. **Key management** — a 32-byte key is generated with `Random.secure()` and
   stored in `flutter_secure_storage` (`pulsr_db_encryption_key_v1`). The key
   reaches drift's database isolate as a captured closure value and is applied
   as `PRAGMA key = "x'<hex>'"` in the setup callback before any statement.
   A build-time flag (`PULSR_DB_ENCRYPTION`, default on) can disable the
   feature; disabling leaves the existing database untouched.
3. **One-shot plaintext migration** — `DatabaseEncryptionBootstrap.prepare()`
   runs before `getIt.init()` in `lib/core/di/injection.dart`. A plaintext file
   (identified by the `SQLite format 3\0` header) is copied into a new encrypted
   file: schema first, then data, then FTS rebuild, then indexes/triggers, with
   `integrity_check` and `foreign_key_check` gates. The plaintext original is
   kept as `<name>.sqlite.plain.bak`; the encrypted copy is verified with the
   key and only then renamed over the live path. WAL/SHM sidecars are folded
   and cleared before the swap so stale pages cannot attach to the new file.
4. **Crash recovery** — on the next start, a leftover `.enc.tmp` that verifies
   with the key is promoted; otherwise a `.plain.bak` is restored. A failure at
   any step leaves a usable database.
5. **Health surfacing** — `DatabaseHealthReport` now exposes
   `migrationFailed`, `encryptionState`, `encryptionCipherAvailable`,
   `encryptionKeyAvailable` and `encryptionDegradedReason`; Settings → Storage
   renders them and offers an FTS repair action.

## Consequences
### Positive
- Library metadata, history and playlists are unreadable without the key on
  every native platform.
- No new package dependency: the cipher comes from the `sqlite3` build hook.
- Failure is non-destructive: unsupported builds, missing secure storage and
  migration errors leave the original database intact and report the state.

### Negative / Trade-offs
- CPU/WAL overhead and a larger binary (the SQLite3MultipleCiphers build).
- Losing the secure-storage key makes an encrypted database unreadable; the
  health report surfaces the mismatch but cannot recover the key.
- Existing users pay a one-time full copy of the database at first launch after
  upgrading.

## Verification
- **Host unit tests** (`test/data/db/database_encryption_test.dart`): cipher
  probe, header detection, key format, real plaintext→encrypted migration with
  data/index/FTS preservation, wrong-key rejection, failed-migration
  preservation, and a real drift open/close/reopen round-trip through the
  database isolate.
- **Device-only checks** (no Android device/AVD available on the reference
  machine): first-launch migration on a populated library, kill-during-migration
  recovery, secure-storage wipe behaviour, and release-APK cipher build
  selection. These must be re-run when hardware is attached.
