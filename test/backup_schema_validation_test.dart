import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/domain/usecases/backup_usecases.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MusicRepository repository;
  late ImportBackupUseCase importUseCase;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MusicRepository(db);
    importUseCase = ImportBackupUseCase(repository, db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ImportBackupUseCase Schema Validation Tests', () {
    test('rejects non-JSON payloads', () async {
      expect(
        () => importUseCase.execute('not a json string'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects root JSON array or primitives', () async {
      expect(
        () => importUseCase.execute(jsonEncode(['item1', 'item2'])),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects payload with missing or invalid version', () async {
      expect(
        () => importUseCase.execute(jsonEncode({'favorites': <dynamic>[]})),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => importUseCase
            .execute(jsonEncode({'version': '1', 'favorites': <dynamic>[]})),
        throwsA(isA<FormatException>()),
      );
      expect(
        () =>
            importUseCase.execute(jsonEncode({'version': 0, 'favorites': <dynamic>[]})),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed favorites (not a list)', () async {
      final payload = {
        'version': 1,
        'favorites': {'invalid': 'structure'},
      };
      expect(
        () => importUseCase.execute(jsonEncode(payload)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed playlists (playlist entry missing name)', () async {
      final payload = {
        'version': 1,
        'playlists': [
          {
            'songPaths': ['/music/song1.mp3']
          },
        ],
      };
      expect(
        () => importUseCase.execute(jsonEncode(payload)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed settings (not a map)', () async {
      final payload = {
        'version': 1,
        'settings': 'invalid_settings_string',
      };
      expect(
        () => importUseCase.execute(jsonEncode(payload)),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts valid schema and returns ImportResult', () async {
      final validPayload = {
        'version': 1,
        'favorites': ['/music/song1.mp3'],
        'playlists': [
          {
            'name': 'Favorites 2026',
            'songPaths': ['/music/song1.mp3'],
          }
        ],
        'settings': {
          'gaplessPlayback': true,
          'crossfadeSeconds': 4.0,
        },
        'playHistory': <dynamic>[],
        'excludedFolders': <dynamic>[],
      };

      final result = await importUseCase.execute(jsonEncode(validPayload));
      expect(result, isA<ImportResult>());
      expect(result.restoredSettingsCount, greaterThan(0));
    });
  });
}
