// lib/data/db/database_encryption.dart
//
// Database encryption at rest (ADR 015).
//
// The library database contains the full local library (paths, titles,
// artists), play history, favourites and playlist membership. This module
// keeps it encrypted when the runtime SQLite flavour supports a cipher
// (SQLite3MultipleCiphers / SQLCipher, selected through the `sqlite3` package
// build hook in pubspec.yaml), migrates an existing plaintext database once,
// and degrades safely — never destructively — when a cipher or the stored key
// is unavailable.
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/error_logger.dart';

/// High-level outcome of [DatabaseEncryptionBootstrap.prepare].
enum DatabaseEncryptionState {
  /// Encryption is disabled by build configuration.
  disabled,

  /// The runtime SQLite build has no cipher support; the database stays
  /// plaintext and the health check reports the degradation.
  unavailable,

  /// A cipher is available and the database is (or will be) encrypted.
  encrypted,

  /// The database was plaintext and has just been migrated to encrypted.
  migrated,

  /// Encryption is expected but could not be established (missing key,
  /// key/database mismatch, migration failure). The database is left
  /// untouched and usable; the health check reports the reason.
  degraded,
}

@immutable
class DatabaseEncryptionStatus {
  final DatabaseEncryptionState state;
  final bool cipherAvailable;

  /// Null when the key could not be read or written.
  final bool? keyAvailable;
  final String? degradedReason;

  const DatabaseEncryptionStatus({
    required this.state,
    required this.cipherAvailable,
    required this.keyAvailable,
    this.degradedReason,
  });

  static const DatabaseEncryptionStatus disabled = DatabaseEncryptionStatus(
    state: DatabaseEncryptionState.disabled,
    cipherAvailable: false,
    keyAvailable: null,
  );

  bool get isEncryptionActive =>
      state == DatabaseEncryptionState.encrypted ||
      state == DatabaseEncryptionState.migrated;

  String get label => switch (state) {
        DatabaseEncryptionState.disabled => 'disabled',
        DatabaseEncryptionState.unavailable => 'unavailable',
        DatabaseEncryptionState.encrypted => 'encrypted',
        DatabaseEncryptionState.migrated => 'migrated',
        DatabaseEncryptionState.degraded => 'degraded',
      };

  Map<String, dynamic> toMap() => {
        'state': label,
        'cipherAvailable': cipherAvailable,
        'keyAvailable': keyAvailable,
        if (degradedReason != null) 'degradedReason': degradedReason,
      };

  @override
  String toString() =>
      'DatabaseEncryptionStatus(state: $label, cipher: $cipherAvailable, '
      'key: $keyAvailable${degradedReason == null ? '' : ', reason: $degradedReason'})';
}

/// Prepares and owns the database key and the one-shot plaintext migration.
///
/// [prepare] must run before the first `AppDatabase` query. `AppDatabase`'s
/// drift setup callback captures the active key and executes `PRAGMA key`
/// before any statement reaches the file.
class DatabaseEncryptionBootstrap {
  DatabaseEncryptionBootstrap._();

  static const String keyStorageKey = 'pulsr_db_encryption_key_v1';
  static const String databaseName = 'pulsr_music_db';

  /// Appended to the live database path while a plaintext copy is being
  /// exported. Kept next to the database so a rename is atomic on the same
  /// filesystem.
  static const String encryptedTempSuffix = '.enc.tmp';
  static const String plaintextBackupSuffix = '.plain.bak';

  static String? _activeKeyHex;
  static DatabaseEncryptionStatus _status = DatabaseEncryptionStatus.disabled;
  static Future<DatabaseEncryptionStatus>? _prepareInFlight;
  static bool _prepared = false;

  /// The raw 32-byte key as lowercase hex, or null when encryption is off.
  static String? get activeKeyHex => _activeKeyHex;

  static DatabaseEncryptionStatus get status => _status;

  /// Test seam: reset process-global preparation state.
  static void debugResetForTesting() {
    _activeKeyHex = null;
    _status = DatabaseEncryptionStatus.disabled;
    _prepareInFlight = null;
    _prepared = false;
  }

  /// Test seam: install a key without secure storage.
  static void debugSetKeyForTesting(String? keyHex) {
    _activeKeyHex = keyHex;
  }

  /// Drift native setup callback: runs in the database isolate before any
  /// statement. Must stay a static tear-off-free closure over the key so the
  /// value is sent to the isolate (globals are not shared across isolates).
  static void applyKey(CommonDatabase rawDatabase, String? keyHex) {
    if (keyHex == null || keyHex.isEmpty) return;
    rawDatabase.execute('PRAGMA key = "x\'$keyHex\'";');
  }

  /// Resolves/creates the key and migrates a plaintext database if needed.
  ///
  /// Never throws: every failure path logs and returns a status. Callers can
  /// continue starting the app; the database is at worst plaintext, which is
  /// exactly the pre-encryption behaviour.
  static Future<DatabaseEncryptionStatus> prepare({
    FlutterSecureStorage? secureStorage,
    Directory? directory,
    bool? enabled,
  }) {
    final inFlight = _prepareInFlight;
    if (inFlight != null) return inFlight;
    if (_prepared) return Future.value(_status);
    final future = _prepareImpl(
      secureStorage: secureStorage,
      directory: directory,
      enabled: enabled,
    );
    _prepareInFlight = future;
    return future.whenComplete(() {
      _prepared = true;
      _prepareInFlight = null;
    });
  }

  static Future<DatabaseEncryptionStatus> _prepareImpl({
    FlutterSecureStorage? secureStorage,
    Directory? directory,
    bool? enabled,
  }) async {
    if (!(enabled ?? AppConfig.databaseEncryptionEnabled)) {
      _status = DatabaseEncryptionStatus.disabled;
      return _status;
    }

    final cipherAvailable = probeCipherSupport();
    if (!cipherAvailable) {
      _status = const DatabaseEncryptionStatus(
        state: DatabaseEncryptionState.unavailable,
        cipherAvailable: false,
        keyAvailable: null,
        degradedReason: 'The SQLite build has no encryption cipher available.',
      );
      ErrorLogger.log(
        'Database encryption unavailable: SQLite build has no cipher. '
        'Database remains plaintext (build with the sqlite3mc hook to enable).',
        category: 'Database',
      );
      return _status;
    }

    String? keyHex;
    try {
      final storage = secureStorage ?? const FlutterSecureStorage();
      keyHex = await storage.read(key: keyStorageKey);
      if (keyHex == null || keyHex.isEmpty) {
        keyHex = generateKeyHex();
        await storage.write(key: keyStorageKey, value: keyHex);
      } else if (!isValidKeyHex(keyHex)) {
        // A corrupted/foreign value must not be used as a raw key.
        keyHex = generateKeyHex();
        await storage.write(key: keyStorageKey, value: keyHex);
      }
    } catch (e, st) {
      _activeKeyHex = null;
      _status = DatabaseEncryptionStatus(
        state: DatabaseEncryptionState.degraded,
        cipherAvailable: cipherAvailable,
        keyAvailable: false,
        degradedReason: 'Secure storage is unavailable: $e',
      );
      ErrorLogger.log('Database key unavailable; continuing plaintext',
          error: e, stackTrace: st, category: 'Database');
      return _status;
    }

    try {
      final docs = directory ?? await getApplicationDocumentsDirectory();
      final live = databaseFileIn(docs);
      final temp = File('${live.path}$encryptedTempSuffix');
      final backup = File('${live.path}$plaintextBackupSuffix');

      // Crash recovery: a previous run may have died between renames.
      _recoverInterruptedMigration(
          live: live, temp: temp, backup: backup, keyHex: keyHex);

      if (!live.existsSync()) {
        _activeKeyHex = keyHex;
        _status = DatabaseEncryptionStatus(
          state: DatabaseEncryptionState.encrypted,
          cipherAvailable: true,
          keyAvailable: true,
        );
        return _status;
      }

      if (isPlaintextSqliteFile(live)) {
        final migrated = encryptPlaintextDatabase(
          plaintext: live,
          keyHex: keyHex,
          backup: backup,
          temp: temp,
        );
        if (migrated) {
          _activeKeyHex = keyHex;
          _status = DatabaseEncryptionStatus(
            state: DatabaseEncryptionState.migrated,
            cipherAvailable: true,
            keyAvailable: true,
          );
          ErrorLogger.log(
            'Database encrypted at rest after plaintext migration '
            '(${live.path})',
            category: 'Database',
          );
          return _status;
        }
        _status = DatabaseEncryptionStatus(
          state: DatabaseEncryptionState.degraded,
          cipherAvailable: true,
          keyAvailable: true,
          degradedReason: 'Plaintext database migration failed; '
              'the original database was preserved.',
        );
        return _status;
      }

      // Non-plaintext header: assumed encrypted. Verify the key before
      // letting the app open it, so a key mismatch is surfaced instead of
      // looking like corruption.
      if (!verifyEncryptedDatabase(live, keyHex)) {
        _status = DatabaseEncryptionStatus(
          state: DatabaseEncryptionState.degraded,
          cipherAvailable: true,
          keyAvailable: true,
          degradedReason: 'The stored key does not open the encrypted '
              'database. The file was left untouched.',
        );
        ErrorLogger.log(
          'Database key verification failed; file left untouched '
          '(${live.path})',
          category: 'Database',
        );
        return _status;
      }

      _activeKeyHex = keyHex;
      _status = DatabaseEncryptionStatus(
        state: DatabaseEncryptionState.encrypted,
        cipherAvailable: true,
        keyAvailable: true,
      );
      return _status;
    } catch (e, st) {
      _status = DatabaseEncryptionStatus(
        state: DatabaseEncryptionState.degraded,
        cipherAvailable: cipherAvailable,
        keyAvailable: true,
        degradedReason: 'Encryption bootstrap failed: $e',
      );
      ErrorLogger.log('Database encryption bootstrap failed',
          error: e, stackTrace: st, category: 'Database');
      return _status;
    }
  }

  static File databaseFileIn(Directory directory) =>
      File('${directory.path}${Platform.pathSeparator}$databaseName.sqlite');

  /// True when the file begins with the SQLite plaintext magic header.
  static bool isPlaintextSqliteFile(File file) {
    if (!file.existsSync()) return false;
    RandomAccessFile? raf;
    try {
      raf = file.openSync();
      if (raf.lengthSync() < 16) return false;
      final header = raf.readSync(16);
      return header.length == 16 &&
          String.fromCharCodes(header) == 'SQLite format 3\u0000';
    } catch (e, st) {
      ErrorLogger.log('Failed to inspect database header',
          error: e, stackTrace: st, category: 'Database');
      return false;
    } finally {
      raf?.closeSync();
    }
  }

  /// Probes the active sqlite3 build for a cipher. SQLite3MultipleCiphers
  /// answers `PRAGMA cipher`, SQLCipher answers `PRAGMA cipher_version`.
  static bool probeCipherSupport() {
    Database? db;
    try {
      db = sqlite3.openInMemory();
      if (db.select('PRAGMA cipher;').isNotEmpty) return true;
      if (db.select('PRAGMA cipher_version;').isNotEmpty) return true;
      return false;
    } catch (e, st) {
      ErrorLogger.log('Cipher probe failed',
          error: e, stackTrace: st, category: 'Database');
      return false;
    } finally {
      db?.close();
    }
  }

  /// True when the key opens the database and a schema query succeeds.
  static bool verifyEncryptedDatabase(File file, String keyHex) {
    Database? db;
    try {
      db = sqlite3.open(file.path);
      applyKey(db, keyHex);
      db.select('SELECT count(*) FROM sqlite_master;');
      return true;
    } catch (e) {
      return false;
    } finally {
      db?.close();
    }
  }

  /// One-shot plaintext -> encrypted migration.
  ///
  /// Copies the schema, data, indexes and triggers into a new encrypted file
  /// (FTS virtual tables are rebuilt), runs integrity/foreign-key checks, then
  /// atomically swaps the files. The plaintext original is kept as [backup]
  /// until the encrypted copy is verified. Returns true on success.
  static bool encryptPlaintextDatabase({
    required File plaintext,
    required String keyHex,
    required File backup,
    required File temp,
  }) {
    if (!plaintext.existsSync()) return false;
    if (temp.existsSync()) temp.deleteSync();
    if (backup.existsSync()) backup.deleteSync();

    _checkpointAndClearWal(plaintext);

    Database? target;
    try {
      target = sqlite3.open(temp.path);
      applyKey(target, keyHex);
      target.execute('PRAGMA foreign_keys = OFF;');
      target.execute("ATTACH DATABASE ? AS source KEY '';", [plaintext.path]);

      final shadowTables = target
          .select("SELECT name FROM pragma_table_list "
              "WHERE schema='source' AND type='shadow';")
          .map((row) => row['name'] as String)
          .toSet();
      final objects =
          target.select('SELECT type, name, sql FROM source.sqlite_master '
              'WHERE sql IS NOT NULL '
              "ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 "
              "WHEN 'trigger' THEN 2 ELSE 3 END;");

      target.execute('BEGIN IMMEDIATE;');
      try {
        // 1. Schema: ordinary tables and views first, then virtual tables.
        for (final object in objects) {
          final type = object['type'] as String;
          final name = object['name'] as String;
          final sql = object['sql'] as String;
          if (type != 'table' && type != 'view') continue;
          if (_shouldSkipObject(name, shadowTables)) continue;
          if (_isVirtualTable(sql)) continue;
          target.execute(sql);
        }
        for (final object in objects) {
          final type = object['type'] as String;
          final name = object['name'] as String;
          final sql = object['sql'] as String;
          if (type != 'table') continue;
          if (_shouldSkipObject(name, shadowTables)) continue;
          if (!_isVirtualTable(sql)) continue;
          target.execute(sql);
        }

        // 2. Data for ordinary tables (virtual tables are rebuilt below).
        for (final object in objects) {
          final type = object['type'] as String;
          final name = object['name'] as String;
          final sql = object['sql'] as String;
          if (type != 'table') continue;
          if (_shouldSkipObject(name, shadowTables)) continue;
          if (_isVirtualTable(sql)) continue;
          target.execute('INSERT INTO "$name" SELECT * FROM source."$name";');
        }

        // 3. Autoincrement high-water marks, when present.
        _copySequenceIfPresent(target);

        // 4. Rebuild FTS indexes from the copied content.
        for (final object in objects) {
          final type = object['type'] as String;
          final name = object['name'] as String;
          final sql = object['sql'] as String;
          if (type != 'table') continue;
          if (_shouldSkipObject(name, shadowTables)) continue;
          if (!_isVirtualTable(sql)) continue;
          if (!sql.toUpperCase().contains('USING FTS')) continue;
          try {
            target.execute('INSERT INTO "$name"("$name") VALUES(\'rebuild\');');
          } catch (e, st) {
            ErrorLogger.log('FTS rebuild during encryption migration failed',
                error: e, stackTrace: st, category: 'Database');
          }
        }

        // 5. Indexes and triggers after the data is in place.
        for (final object in objects) {
          final type = object['type'] as String;
          if (type != 'index' && type != 'trigger') continue;
          target.execute(object['sql'] as String);
        }

        final integrity = target.select('PRAGMA integrity_check;');
        final integrityValue =
            integrity.isEmpty ? 'unknown' : '${integrity.first.values.first}';
        if (integrityValue.toLowerCase() != 'ok') {
          throw StateError('integrity_check failed: $integrityValue');
        }
        final fkViolations = target.select('PRAGMA foreign_key_check;');
        if (fkViolations.isNotEmpty) {
          throw StateError(
              'foreign_key_check found ${fkViolations.length} violation(s)');
        }
        target.execute('COMMIT;');
        try {
          target.execute('DETACH DATABASE source;');
        } catch (_) {
          // Disposing the connection detaches automatically.
        }
      } catch (e) {
        try {
          target.execute('ROLLBACK;');
        } catch (_) {
          // The transaction may already be aborted; the temp file is deleted
          // below either way.
        }
        rethrow;
      }
      target.close();
      target = null;
      _clearWal(temp);

      if (!verifyEncryptedDatabase(temp, keyHex)) {
        throw StateError('encrypted copy did not verify with the key');
      }

      plaintext.renameSync(backup.path);
      temp.renameSync(plaintext.path);
      _clearWal(plaintext);
      ErrorLogger.log('Plaintext database backed up to ${backup.path}',
          category: 'Database');
      return true;
    } catch (e, st) {
      ErrorLogger.log('Plaintext database encryption migration failed',
          error: e, stackTrace: st, category: 'Database');
      try {
        target?.close();
      } catch (_) {}
      if (temp.existsSync()) {
        try {
          temp.deleteSync();
        } catch (_) {}
      }
      // If the original was already moved to backup but the replacement
      // failed, restore it so the library is never lost.
      if (!plaintext.existsSync() && backup.existsSync()) {
        try {
          backup.renameSync(plaintext.path);
        } catch (restoreError, restoreStack) {
          ErrorLogger.log('Failed to restore plaintext database backup',
              error: restoreError,
              stackTrace: restoreStack,
              category: 'Database');
        }
      }
      return false;
    } finally {
      target?.close();
    }
  }

  static void _recoverInterruptedMigration({
    required File live,
    required File temp,
    required File backup,
    required String keyHex,
  }) {
    try {
      if (!live.existsSync() && temp.existsSync()) {
        if (verifyEncryptedDatabase(temp, keyHex)) {
          temp.renameSync(live.path);
          _clearWal(live);
          ErrorLogger.log(
            'Recovered interrupted database encryption: promoted verified '
            'encrypted copy',
            category: 'Database',
          );
          return;
        }
        temp.deleteSync();
      }
      if (!live.existsSync() && backup.existsSync()) {
        backup.renameSync(live.path);
        _clearWal(live);
        ErrorLogger.log(
          'Recovered interrupted database encryption: restored plaintext '
          'backup',
          category: 'Database',
        );
      }
    } catch (e, st) {
      ErrorLogger.log('Database encryption recovery failed',
          error: e, stackTrace: st, category: 'Database');
    }
  }

  static bool _shouldSkipObject(String name, Set<String> shadowTables) =>
      shadowTables.contains(name) ||
      name.startsWith('sqlite_') ||
      name == 'sqlite_sequence';

  static bool _isVirtualTable(String sql) =>
      sql.trimLeft().toUpperCase().startsWith('CREATE VIRTUAL');

  static void _copySequenceIfPresent(Database target) {
    try {
      final hasSource = target.select(
          "SELECT name FROM source.sqlite_master WHERE name='sqlite_sequence';");
      if (hasSource.isEmpty) return;
      final hasTarget = target.select(
          "SELECT name FROM sqlite_master WHERE name='sqlite_sequence';");
      if (hasTarget.isEmpty) return;
      target.execute('DELETE FROM sqlite_sequence;');
      target.execute(
          'INSERT INTO sqlite_sequence SELECT * FROM source.sqlite_sequence;');
    } catch (e, st) {
      ErrorLogger.log('Failed to copy sqlite_sequence during migration',
          error: e, stackTrace: st, category: 'Database');
    }
  }

  /// Folds the WAL into the main file so the migration copies a complete
  /// database and stale `-wal`/`-shm` files cannot attach to the new file.
  static void _checkpointAndClearWal(File database) {
    Database? db;
    try {
      db = sqlite3.open(database.path);
      db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (e, st) {
      ErrorLogger.log('WAL checkpoint before database encryption failed',
          error: e, stackTrace: st, category: 'Database');
    } finally {
      db?.close();
    }
    _clearWal(database);
  }

  static void _clearWal(File database) {
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${database.path}$suffix');
      try {
        if (sidecar.existsSync()) sidecar.deleteSync();
      } catch (e, st) {
        ErrorLogger.log('Failed to remove database sidecar ${sidecar.path}',
            error: e, stackTrace: st, category: 'Database');
      }
    }
  }

  /// 32 random bytes as lowercase hex (64 chars), the raw-key form
  /// `PRAGMA key = "x'<hex>'"` expects.
  static String generateKeyHex({Random? random}) {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool isValidKeyHex(String value) =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  @visibleForTesting
  static String? get storedKeyForTesting => _activeKeyHex;
}
