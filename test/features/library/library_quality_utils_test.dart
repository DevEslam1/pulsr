// Unit coverage for the shared Library lossless predicate and the alphabet
// rail's letter resolution (the '#' bucket must reach digit/symbol titles).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/library/presentation/library_quality_utils.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';

import 'library_test_harness.dart';

SongsTableData song({
  String? codec,
  int? bitDepth,
  String path = '/music/song.mp3',
}) =>
    testSong(id: 1, path: path).copyWith(
      codec: Value(codec),
      bitDepth: Value(bitDepth),
    );

void main() {
  group('isLosslessSong', () {
    test('matches lossless codecs case-insensitively', () {
      expect(isLosslessSong(song(codec: 'flac')), isTrue);
      expect(isLosslessSong(song(codec: 'FLAC')), isTrue);
      expect(isLosslessSong(song(codec: 'Alac')), isTrue);
      expect(isLosslessSong(song(codec: 'wav', bitDepth: 16)), isTrue);
      expect(isLosslessSong(song(codec: 'AIFF')), isTrue);
      expect(isLosslessSong(song(codec: 'mp3')), isFalse);
    });

    test('falls back to the path extension when the codec is null', () {
      expect(isLosslessSong(song(path: '/music/album.flac')), isTrue);
      expect(isLosslessSong(song(path: '/music/album.FLAC')), isTrue);
      expect(isLosslessSong(song(path: '/music/album.aiff')), isTrue);
      expect(isLosslessSong(song(path: '/music/album.dsf')), isTrue);
      expect(isLosslessSong(song(path: '/music/album.mp3')), isFalse);
    });

    test('counts >= 24-bit depth even without codec or extension', () {
      expect(isLosslessSong(song(bitDepth: 24)), isTrue);
      expect(isLosslessSong(song(bitDepth: 16)), isFalse);
    });
  });

  group('libraryRailLetterIndex', () {
    test('letters match the case-insensitive title initial', () {
      final songs = [
        testSong(id: 1, title: 'alpha'),
        testSong(id: 2, title: 'Beta'),
      ];
      expect(libraryRailLetterIndex('A', songs), 0);
      expect(libraryRailLetterIndex('B', songs), 1);
      expect(libraryRailLetterIndex('Z', songs), -1);
    });

    test('# buckets digit, symbol and non-Latin initials', () {
      final songs = [
        testSong(id: 1, title: 'Alpha'),
        testSong(id: 2, title: '123 Song'),
        testSong(id: 3, title: '! Bang'),
        testSong(id: 4, title: 'طرب'),
      ];
      expect(libraryRailLetterIndex('#', songs), 1);
      expect(
          libraryRailLetterIndex('#', [testSong(id: 9, title: '# Hash')]), 0);
      expect(
          libraryRailLetterIndex('#', [testSong(id: 9, title: 'Alpha')]), -1);
    });
  });
}
