// Code-hygiene guards for defect classes that are cheap to reintroduce and
// expensive to notice. These tests scan lib/ directly, so they fail the moment
// the pattern comes back rather than when a user reports the symptom.
//
// Introduced by remediation tranche 1 (defects 08-04 and 01-01).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/controllers/queue_slot_data.dart';

void main() {
  group('code hygiene guards', () {
    // Baseline counted at commit 09ce0cb plus remediation tranches 1-2. Lower
    // this constant as empty catch bodies are fixed; never raise it.
    // 439 -> 438 after scrobbler/headset logging pass (14 sites fixed).
    // 438 -> 435 after service-layer logging pass (waveform/ytm-cache/
    // artist-bio/lrclib/artwork/metadata/cloud-sync).
    const int emptyCatchBaseline = 435;

    List<File> dartFilesUnderLib() {
      final dir = Directory('lib');
      if (!dir.existsSync()) {
        fail('lib/ not found from ${Directory.current.path} - run from the '
            'repository root');
      }
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
    }

    test('lib/ contains no raw print() calls (defect 08-04)', () {
      final printCall = RegExp(r'\bprint\s*\(');
      final offenders = <String>[];

      for (final file in dartFilesUnderLib()) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) continue;
          if (printCall.hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'raw print() writes to the release console and bypasses '
              'ErrorLogger/Sentry. Use ErrorLogger.log instead. Found:\n'
              '${offenders.join('\n')}');
    });

    test('empty catch bodies do not increase (defect 01-01 ratchet)', () {
      // `catch (...) {}` swallows a failure with no user signal and no
      // telemetry. The ratchet allows the existing baseline and forces the
      // number down over time, instead of blocking the whole remediation.
      final emptyCatch = RegExp(r'catch\s*\([^)]*\)\s*\{\s*\}');

      var count = 0;
      for (final file in dartFilesUnderLib()) {
        count += emptyCatch.allMatches(file.readAsStringSync()).length;
      }

      expect(count, lessThanOrEqualTo(emptyCatchBaseline),
          reason: 'empty catch bodies swallow failures silently. Baseline is '
              '$emptyCatchBaseline; fix existing ones and lower the constant, '
              'but never add new ones. Actual: $count');
    });

    test('every Player controller is strictly <= 400 lines (A1 / Hygiene)', () {
      final controllersDir = Directory('lib/features/player/cubit/controllers');
      expect(controllersDir.existsSync(), isTrue);

      final controllerFiles = controllersDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_controller.dart'))
          .toList();

      expect(controllerFiles, isNotEmpty);

      final overLimit = <String>[];
      for (final file in controllerFiles) {
        final lines = file.readAsLinesSync().length;
        if (lines > 400) {
          overLimit.add('${file.path}: $lines lines (max 400)');
        }
      }

      expect(overLimit, isEmpty,
          reason: 'Controllers must remain focused and <= 400 lines');
    });

    test('domain boundary interfaces provide comprehensive contract documentation', () {
      final boundaryFile = File('lib/domain/boundaries.dart');
      expect(boundaryFile.existsSync(), isTrue);
      final content = boundaryFile.readAsStringSync();
      expect(content.contains('/// Boundary contract:'), isTrue);
      expect(content.contains('abstract class IPlayerSettingsBoundary'), isTrue);
      expect(content.contains('abstract class IPlayerLibraryBoundary'), isTrue);
      expect(content.contains('abstract class IDownloadPlayerBoundary'), isTrue);
    });

    test('calculateReorderedIndex shifts active pointer correctly across permutations', () {
      // 1. Moving current index itself
      expect(calculateReorderedIndex(2, 5, 2), equals(5));

      // 2. Moving item before current index to after current index
      expect(calculateReorderedIndex(1, 4, 3), equals(2));

      // 3. Moving item after current index to before current index
      expect(calculateReorderedIndex(4, 1, 2), equals(3));

      // 4. Moving item entirely outside current index position
      expect(calculateReorderedIndex(5, 7, 2), equals(2));
      expect(calculateReorderedIndex(0, 1, 4), equals(4));
    });

    test('calculateRemovedIndex adjusts active pointer accurately for all positions', () {
      // 1. Empty queue returns 0
      expect(calculateRemovedIndex(0, 0, 0), equals(0));

      // 2. Removing item before current shifts current left
      expect(calculateRemovedIndex(1, 3, 5), equals(2));

      // 3. Removing item after current keeps current
      expect(calculateRemovedIndex(4, 2, 5), equals(2));

      // 4. Removing current item clamps to new bounds
      expect(calculateRemovedIndex(4, 4, 4), equals(3));
      expect(calculateRemovedIndex(0, 0, 3), equals(0));
    });

    test('QueueSlotData correctly hydrates matching entities and drops unresolvable IDs', () {
      const slot = QueueSlotData(
        songIds: [101, 102, 103],
        currentIndex: 1,
        position: Duration(seconds: 45),
      );

      final Map<int, SongsTableData> mockLookup = {
        101: const SongsTableData(
          id: 101,
          title: 'Track A',
          artist: 'Artist A',
          album: 'Album A',
          path: '/path/a',
          durationMs: 120000,
          dateAdded: 0,
          isFavorite: false,
          isMissing: false,
          playCount: 0,
          lastPositionMs: 0,
          source: 'local',
          isDownloaded: true,
          year: 2024,
        ),
        103: const SongsTableData(
          id: 103,
          title: 'Track C',
          artist: 'Artist C',
          album: 'Album C',
          path: '/path/c',
          durationMs: 180000,
          dateAdded: 0,
          isFavorite: false,
          isMissing: false,
          playCount: 0,
          lastPositionMs: 0,
          source: 'local',
          isDownloaded: true,
          year: 2024,
        ),
      };

      final hydrated = slot.songsFrom(mockLookup);
      expect(hydrated.length, equals(2));
      expect(hydrated[0].id, equals(101));
      expect(hydrated[1].id, equals(103));
      expect(slot.currentIndex, equals(1));
      expect(slot.position, equals(const Duration(seconds: 45)));
    });
  });
}
