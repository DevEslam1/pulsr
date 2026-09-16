// Regression tests for the audit fixes.
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/core/services/duplicate_finder_service.dart';
import 'package:pulsr/data/audio/format_aware_decoder.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_quality_info.dart';
import 'package:pulsr/domain/services/room_correction_service.dart';

SongsTableData _song({
  required int id,
  required String title,
  required String artist,
  required String path,
  int? durationMs,
  int? fileSize,
}) {
  return SongsTableData(
    id: id,
    title: title,
    artist: artist,
    album: 'Album',
    durationMs: durationMs ?? 200000,
    path: path,
    source: SongSource.local,
    isFavorite: false,
    isMissing: false,
    playCount: 0,
    lastPositionMs: 0,
    isDownloaded: false,
    fileSize: fileSize,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DoP transport flag reset (HIGH)', () {
    test('decodeForFormat clears a stale dsdDopActive flag', () async {
      // Simulate the previous track having used DoP.
      AudioQualityInfo.dsdDopActive = true;

      final decoder = FormatAwareDecoder(
        resolveYtmStream: (song, tag) async =>
            AudioSource.uri(Uri.parse('https://example.com')),
      );

      final song = _song(
        id: 1,
        title: 'Plain MP3',
        artist: 'Artist',
        path: '/storage/music/track.mp3',
      );

      await decoder.decodeForFormat(song, MediaItem(id: '1', title: 'Plain MP3'));
      expect(AudioQualityInfo.dsdDopActive, isFalse,
          reason: 'a non-DSD track must not inherit the previous DoP state');
    });
  });

  group('DuplicateFinderService (HIGH)', () {
    test('emits every checksum cluster, not just the first', () async {
      final dir = await Directory.systemTemp.createTemp('dup_test');
      try {
        final a1 = File('${dir.path}/a1.bin');
        final a2 = File('${dir.path}/a2.bin');
        final b1 = File('${dir.path}/b1.bin');
        final b2 = File('${dir.path}/b2.bin');
        await a1.writeAsBytes(List<int>.filled(2048, 7));
        await a2.writeAsBytes(List<int>.filled(2048, 7));
        await b1.writeAsBytes(List<int>.filled(2048, 9));
        await b2.writeAsBytes(List<int>.filled(2048, 9));

        final songs = [
          _song(id: 1, title: 'Alpha', artist: 'A', path: a1.path, fileSize: 2048),
          _song(id: 2, title: 'Beta', artist: 'B', path: a2.path, fileSize: 2048),
          _song(id: 3, title: 'Gamma', artist: 'C', path: b1.path, fileSize: 2048),
          _song(id: 4, title: 'Delta', artist: 'D', path: b2.path, fileSize: 2048),
        ];

        final groups = await DuplicateFinderService().findDuplicates(songs);
        expect(groups.length, 2,
            reason: 'both checksum clusters must be reported');
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('RoomCorrectionService.exportCorrectionImpulseResponse', () {
    test('returns an empty IR on mismatched gains/centers', () {
      final ir = RoomCorrectionService.exportCorrectionImpulseResponse(
        const [1.0, 2.0, 3.0],
        centers: const [100.0, 1000.0],
      );
      expect(ir, isEmpty,
          reason: 'mismatched lengths must not yield a silent pass-through');
    });

    test('designs a non-empty IR for valid input', () {
      final ir = RoomCorrectionService.exportCorrectionImpulseResponse(
        const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      );
      expect(ir, isNotEmpty);
      expect(ir, isA<Float32List>());
    });
  });
}
