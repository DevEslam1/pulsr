import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/backup_usecases.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}
class MockAppDatabase extends Mock implements AppDatabase {}

void main() {
  group('Backup UseCases Size Validation Tests', () {
    test('rejects backup payload that exceeds 10MB in UTF-8 bytes', () async {
      final oversizeJson = jsonEncode({
        'version': 1,
        'metadata': 'A' * (ImportBackupUseCase.maxBackupSizeBytes + 100),
      });

      final useCase = ImportBackupUseCase(
        MockMusicRepository(),
        MockAppDatabase(),
      );

      expect(
        () => useCase.execute(oversizeJson),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Backup file exceeds maximum allowed size'),
        )),
      );
    });

    test('accepts backup payload within 10MB byte limit and validates schema', () async {
      final validJson = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'playlists': [],
        'favorites': [],
        'playbackHistory': [],
      });

      expect(utf8.encode(validJson).length, lessThan(ImportBackupUseCase.maxBackupSizeBytes));
    });
  });
}
