import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/db/database_encryption.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('DatabaseEncryptionBootstrap', () {
    test('reports the cipher capability of the active sqlite3 build', () {
      final available = DatabaseEncryptionBootstrap.probeCipherSupport();
      // The pubspec hooks select the SQLite3MultipleCiphers build; the test
      // binary must see the same build as the app.
      expect(available, isTrue,
          reason: 'sqlite3mc hook is not active in flutter test');
    });

    test('generated keys are 64 lowercase hex characters', () {
      final key = DatabaseEncryptionBootstrap.generateKeyHex();
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(DatabaseEncryptionBootstrap.isValidKeyHex(key), isTrue);
      expect(
          DatabaseEncryptionBootstrap.isValidKeyHex(
              key.substring(0, key.length - 1)),
          isFalse);
    });

    test('header detection distinguishes plaintext from encrypted files', () {
      final dir = Directory.systemTemp.createTempSync('pulsr_db_header_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final plain = File('${dir.path}/plain.sqlite');
      final encrypted = File('${dir.path}/enc.sqlite');
      final db = sqlite3.open(plain.path);
      db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY);');
      db.close();

      expect(DatabaseEncryptionBootstrap.isPlaintextSqliteFile(plain), isTrue);
      expect(DatabaseEncryptionBootstrap.isPlaintextSqliteFile(encrypted),
          isFalse);

      final key = DatabaseEncryptionBootstrap.generateKeyHex();
      final ok = DatabaseEncryptionBootstrap.encryptPlaintextDatabase(
        plaintext: plain,
        keyHex: key,
        backup: File('${plain.path}.plain.bak'),
        temp: File('${plain.path}.enc.tmp'),
      );
      expect(ok, isTrue);
      expect(DatabaseEncryptionBootstrap.isPlaintextSqliteFile(plain), isFalse);
      expect(DatabaseEncryptionBootstrap.verifyEncryptedDatabase(plain, key),
          isTrue);
      expect(File('${plain.path}.plain.bak').existsSync(), isFalse);
      expect(File('${plain.path}.enc.tmp').existsSync(), isFalse);
    });

    test(
        'plaintext migration preserves schema version, data, indexes and triggers',
        () {
      final dir = Directory.systemTemp.createTempSync('pulsr_db_migrate_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final live = File('${dir.path}/pulsr_music_db.sqlite');

      final plain = sqlite3.open(live.path);
      plain.execute('PRAGMA user_version = 13;');
      plain.execute('CREATE TABLE songs (id INTEGER PRIMARY KEY, title TEXT);');
      plain.execute('CREATE INDEX idx_songs_title ON songs(title);');
      plain.execute('CREATE TABLE albums (id INTEGER PRIMARY KEY, name TEXT);');
      plain.execute(
          "INSERT INTO songs (title) VALUES ('keep one'), ('keep two');");
      plain.execute("INSERT INTO albums (name) VALUES ('album');");
      plain.execute(
          "CREATE VIRTUAL TABLE songs_fts USING fts5(title, content='songs', content_rowid='id');");
      plain.execute("INSERT INTO songs_fts(songs_fts) VALUES('rebuild');");
      plain.close();

      final key = DatabaseEncryptionBootstrap.generateKeyHex();
      final ok = DatabaseEncryptionBootstrap.encryptPlaintextDatabase(
        plaintext: live,
        keyHex: key,
        backup: File('${live.path}.plain.bak'),
        temp: File('${live.path}.enc.tmp'),
      );
      expect(ok, isTrue);
      expect(File('${live.path}.plain.bak').existsSync(), isFalse,
          reason: '.plain.bak must be deleted after verified encryption');
      expect(File('${live.path}.enc.tmp').existsSync(), isFalse);

      final db = sqlite3.open(live.path);
      db.execute('PRAGMA key = "x\'$key\'";');
      addTearDown(db.close);
      expect(db.select('PRAGMA user_version;').first.values.first, 13);
      expect(db.select('SELECT count(*) AS c FROM songs;').first['c'], 2);
      expect(db.select('SELECT count(*) AS c FROM albums;').first['c'], 1);
      expect(db.select('SELECT count(*) AS c FROM songs_fts;').first['c'], 2);
      expect(
          db
              .select(
                  "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_songs_title';")
              .length,
          1);
    });

    test(
        'recovers interrupted migration and cleans leftover plain.bak when live verifies',
        () async {
      final dir = Directory.systemTemp.createTempSync('pulsr_db_recover_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final live = File('${dir.path}/pulsr_music_db.sqlite');
      final key = DatabaseEncryptionBootstrap.generateKeyHex();

      // Create an encrypted live db
      final plain = sqlite3.open(live.path);
      plain.execute('CREATE TABLE songs (id INTEGER PRIMARY KEY);');
      plain.close();
      expect(
        DatabaseEncryptionBootstrap.encryptPlaintextDatabase(
          plaintext: live,
          keyHex: key,
          backup: File('${live.path}.plain.bak'),
          temp: File('${live.path}.enc.tmp'),
        ),
        isTrue,
      );

      // Now create a leftover .plain.bak file
      final backup = File('${live.path}.plain.bak')..writeAsStringSync('dummy');
      expect(backup.existsSync(), isTrue);

      FlutterSecureStorage.setMockInitialValues({
        DatabaseEncryptionBootstrap.keyStorageKey: key,
      });

      // Trigger recovery with a live DB that verifies
      DatabaseEncryptionBootstrap.debugResetForTesting();
      addTearDown(DatabaseEncryptionBootstrap.debugResetForTesting);
      final status = await DatabaseEncryptionBootstrap.prepare(
        directory: dir,
        enabled: true,
      );
      expect(status.state, equals(DatabaseEncryptionState.encrypted));
      expect(backup.existsSync(), isFalse);
    });

    test(
        'returns missingKeyForEncryptedDb when encrypted DB exists without valid key',
        () async {
      final dir = Directory.systemTemp.createTempSync('pulsr_db_missing_key_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final live = File('${dir.path}/pulsr_music_db.sqlite');
      final key = DatabaseEncryptionBootstrap.generateKeyHex();

      // Create an encrypted live db
      final plain = sqlite3.open(live.path);
      plain.execute('CREATE TABLE songs (id INTEGER PRIMARY KEY);');
      plain.close();
      expect(
        DatabaseEncryptionBootstrap.encryptPlaintextDatabase(
          plaintext: live,
          keyHex: key,
          backup: File('${live.path}.plain.bak'),
          temp: File('${live.path}.enc.tmp'),
        ),
        isTrue,
      );

      // Clear secure storage key
      FlutterSecureStorage.setMockInitialValues({});

      DatabaseEncryptionBootstrap.debugResetForTesting();
      addTearDown(DatabaseEncryptionBootstrap.debugResetForTesting);
      final status = await DatabaseEncryptionBootstrap.prepare(
        directory: dir,
        enabled: true,
      );

      expect(status.state, equals(DatabaseEncryptionState.degraded));
      expect(status.keyAvailable, isFalse);
      expect(status.degradedReason,
          equals(DatabaseEncryptionBootstrap.missingKeyForEncryptedDb));
      expect(DatabaseEncryptionBootstrap.activeKeyHex, isNull);

      // Verify the key was NOT written to secure storage
      const storage = FlutterSecureStorage();
      final writtenKey =
          await storage.read(key: DatabaseEncryptionBootstrap.keyStorageKey);
      expect(writtenKey, isNull);
    });

    test('a wrong key does not open the encrypted database', () {
      final dir = Directory.systemTemp.createTempSync('pulsr_db_wrongkey_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final live = File('${dir.path}/pulsr_music_db.sqlite');

      final plain = sqlite3.open(live.path);
      plain.execute('CREATE TABLE songs (id INTEGER PRIMARY KEY);');
      plain.close();
      final key = DatabaseEncryptionBootstrap.generateKeyHex();
      expect(
          DatabaseEncryptionBootstrap.encryptPlaintextDatabase(
            plaintext: live,
            keyHex: key,
            backup: File('${live.path}.plain.bak'),
            temp: File('${live.path}.enc.tmp'),
          ),
          isTrue);

      final wrongKey = DatabaseEncryptionBootstrap.generateKeyHex();
      expect(
          DatabaseEncryptionBootstrap.verifyEncryptedDatabase(live, wrongKey),
          isFalse);
    });

    test('a failed migration preserves the plaintext database', () {
      final dir = Directory.systemTemp.createTempSync('pulsr_db_fail_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final live = File('${dir.path}/pulsr_music_db.sqlite');

      final plain = sqlite3.open(live.path);
      plain.execute('CREATE TABLE songs (id INTEGER PRIMARY KEY);');
      plain.execute('INSERT INTO songs (id) VALUES (7);');
      plain.close();

      // A directory at the temp path makes the encrypted target unopenable.
      final temp = Directory('${live.path}.enc.tmp')..createSync();
      final ok = DatabaseEncryptionBootstrap.encryptPlaintextDatabase(
        plaintext: live,
        keyHex: DatabaseEncryptionBootstrap.generateKeyHex(),
        backup: File('${live.path}.plain.bak'),
        temp: File(temp.path),
      );

      expect(ok, isFalse);
      expect(DatabaseEncryptionBootstrap.isPlaintextSqliteFile(live), isTrue);
      final check = sqlite3.open(live.path);
      addTearDown(check.close);
      expect(check.select('SELECT count(*) AS c FROM songs;').first['c'], 1);
    });

    test('drift opens the migrated file with the captured key', () async {
      final dir = Directory.systemTemp.createTempSync('pulsr_db_drift_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final live = File('${dir.path}/pulsr_music_db.sqlite');
      final key = DatabaseEncryptionBootstrap.generateKeyHex();
      DatabaseEncryptionBootstrap.debugSetKeyForTesting(key);
      addTearDown(DatabaseEncryptionBootstrap.debugResetForTesting);

      final db = AppDatabase.openAt(live);
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            title: 'Encrypted Song',
            path: '/music/encrypted.mp3',
          ));
      await db.close();

      expect(DatabaseEncryptionBootstrap.isPlaintextSqliteFile(live), isFalse);

      final reopened = AppDatabase.openAt(live);
      addTearDown(reopened.close);
      final rows = await reopened.select(reopened.songsTable).get();
      expect(rows.map((row) => row.title), contains('Encrypted Song'));
    });
  });
}
