// Coverage for DynamicThemeCubit: state copy semantics, reset behaviour,
// debounce/token handling and palette extraction (local artwork cache, remote
// URL cache, failure fallbacks).
//
// Palette decoding is engine-backed real async work, so extraction tests run
// inside `tester.runAsync`; the debounce and palette timeouts are then real
// timers. The on_audio_query method channel is stubbed to return null, so no
// plugin or network I/O leaves the test process.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/core/widgets/cached_artwork.dart';
import 'package:pulsr/data/db/app_database.dart';

/// 4x4 PNG (red and blue halves) encoded for MemoryImage palette extraction.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAAXNSR0IArs4c6QAAAARnQU1BAACx'
    'jwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAWSURBVBhXY5ALuPMfhO9o2IAxA+kCAMOQJEG8'
    'O4sXAAAAAElFTkSuQmCC';

const _audioQueryChannel = MethodChannel('com.lucasjosino.on_audio_query');

SongsTableData _song(int id) => SongsTableData(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      album: 'Album',
      albumId: 1,
      durationMs: 1000,
      path: '/music/$id.mp3',
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      source: 'local',
      isDownloaded: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioQueryChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioQueryChannel, null);
  });

  group('DynamicThemeState', () {
    test('defaults match the brand palette', () {
      const state = DynamicThemeState();
      expect(state.primaryColor, AppColors.primary);
      expect(state.secondaryColor, AppColors.secondary);
      expect(state.backgroundColor, AppColors.background);
      expect(state.surfaceColor, AppColors.surface);
      expect(state.isDark, isTrue);
      expect(state.hasCustomArtworkColor, isFalse);
    });

    test('copyWith replaces only the supplied fields', () {
      const base = DynamicThemeState();
      final copy = base.copyWith(
        primaryColor: Colors.red,
        isDark: false,
        hasCustomArtworkColor: true,
      );
      expect(copy.primaryColor, Colors.red);
      expect(copy.secondaryColor, AppColors.secondary);
      expect(copy.backgroundColor, AppColors.background);
      expect(copy.surfaceColor, AppColors.surface);
      expect(copy.isDark, isFalse);
      expect(copy.hasCustomArtworkColor, isTrue);

      final untouched = base.copyWith();
      expect(untouched.primaryColor, AppColors.primary);
      expect(untouched.isDark, isTrue);
    });
  });

  group('DynamicThemeCubit reset semantics', () {
    testWidgets('resetToDefault restores palette but preserves the dark flag',
        (tester) async {
      final cubit = DynamicThemeCubit();
      addTearDown(cubit.close);

      cubit.safeEmit(const DynamicThemeState(
        primaryColor: Colors.red,
        secondaryColor: Colors.green,
        backgroundColor: Colors.black,
        surfaceColor: Colors.grey,
        isDark: false,
        hasCustomArtworkColor: true,
      ));
      final states = <DynamicThemeState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      cubit.resetToDefault();
      await tester.pump();

      expect(states, hasLength(1));
      expect(states.single.primaryColor, AppColors.primary);
      expect(states.single.secondaryColor, AppColors.secondary);
      expect(states.single.hasCustomArtworkColor, isFalse);
      expect(states.single.isDark, isFalse);
    });

    testWidgets('updateFromSong(null) resets to the default palette',
        (tester) async {
      final cubit = DynamicThemeCubit();
      addTearDown(cubit.close);
      cubit.safeEmit(const DynamicThemeState(
        primaryColor: Colors.red,
        isDark: false,
        hasCustomArtworkColor: true,
      ));
      await cubit.updateFromSong(null);
      expect(cubit.state.primaryColor, AppColors.primary);
      expect(cubit.state.isDark, isFalse);
      expect(cubit.state.hasCustomArtworkColor, isFalse);
    });

    testWidgets('after close both reset entry points are inert',
        (tester) async {
      final cubit = DynamicThemeCubit();
      final states = <DynamicThemeState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);
      await cubit.close();

      cubit.resetToDefault();
      await cubit.updateFromSong(null);
      await tester.pump();
      expect(states, isEmpty);
    });
  });

  group('DynamicThemeCubit palette extraction', () {
    testWidgets('missing artwork settles back to the default palette',
        (tester) async {
      final cubit = DynamicThemeCubit();
      addTearDown(cubit.close);
      cubit.safeEmit(const DynamicThemeState(
        primaryColor: Colors.red,
        isDark: false,
        hasCustomArtworkColor: true,
      ));
      final states = <DynamicThemeState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      await tester.runAsync(() async {
        unawaited(cubit.updateFromDetails(songId: 880001));
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      });
      await tester.pump();

      expect(states, isNotEmpty);
      expect(states.last.primaryColor, AppColors.primary);
      expect(states.last.isDark, isFalse);
      expect(states.last.hasCustomArtworkColor, isFalse);
    });

    testWidgets(
        'updateFromSongId and updateFromSong route through the debounce',
        (tester) async {
      final cubit = DynamicThemeCubit();
      addTearDown(cubit.close);
      final states = <DynamicThemeState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      await tester.runAsync(() async {
        unawaited(cubit.updateFromSongId(880002));
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      });
      await tester.pump();

      await tester.runAsync(() async {
        unawaited(cubit.updateFromSong(_song(880003)));
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      });
      await tester.pump();

      expect(states, hasLength(2));
      expect(states.last.hasCustomArtworkColor, isFalse);
    });

    testWidgets('cached local artwork produces and reuses a custom palette',
        (tester) async {
      final cache = ArtworkLruCache();
      cache.put('AUDIO_880004', base64Decode(_pngBase64), persistToDisk: false);
      final cubit = DynamicThemeCubit();
      addTearDown(cubit.close);
      final states = <DynamicThemeState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      await tester.runAsync(() async {
        unawaited(cubit.updateFromDetails(songId: 880004));
        await Future<void>.delayed(const Duration(milliseconds: 2500));
      });
      await tester.pump();

      expect(states, isNotEmpty);
      expect(states.last.hasCustomArtworkColor, isTrue);
      final extractedPrimary = states.last.primaryColor;

      // Second call for the same artwork hits the in-memory palette cache.
      unawaited(cubit.updateFromDetails(songId: 880004));
      await tester.pump();
      await tester.pump();

      expect(states.last.hasCustomArtworkColor, isTrue);
      expect(states.last.primaryColor, extractedPrimary);
    });

    testWidgets(
        'remote artwork served from the image cache uses the high-res key',
        (tester) async {
      const url = 'https://i.ytimg.com/vi/unit/hqdefault.jpg';
      final upgraded = CachedArtwork.upgradeToHighResArtwork(url);
      expect(upgraded, contains('maxresdefault.jpg'));
      ArtworkLruCache()
          .put(upgraded, base64Decode(_pngBase64), persistToDisk: false);
      final cubit = DynamicThemeCubit();
      addTearDown(cubit.close);
      final states = <DynamicThemeState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      await tester.runAsync(() async {
        unawaited(cubit.updateFromDetails(
          songId: 880005,
          remoteArtworkUrl: url,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 2500));
      });
      await tester.pump();

      expect(states, isNotEmpty);
      expect(states.last.hasCustomArtworkColor, isTrue);
    });

    testWidgets('rapid requests for one song collapse into a single extraction',
        (tester) async {
      final cache = ArtworkLruCache();
      cache.put('AUDIO_880006', base64Decode(_pngBase64), persistToDisk: false);
      final cubit = DynamicThemeCubit();
      addTearDown(cubit.close);
      final states = <DynamicThemeState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      await tester.runAsync(() async {
        unawaited(cubit.updateFromDetails(songId: 880006));
        unawaited(cubit.updateFromDetails(songId: 880006));
        await Future<void>.delayed(const Duration(milliseconds: 2500));
      });
      await tester.pump();

      expect(states, hasLength(1));
      expect(states.single.hasCustomArtworkColor, isTrue);
    });

    testWidgets('a remote palette failure with no prior palette keeps state',
        (tester) async {
      final cubit = DynamicThemeCubit();
      addTearDown(cubit.close);
      cubit.safeEmit(const DynamicThemeState(
        primaryColor: Colors.red,
        hasCustomArtworkColor: true,
      ));
      final states = <DynamicThemeState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      await tester.runAsync(() async {
        unawaited(cubit.updateFromDetails(
          songId: 880007,
          remoteArtworkUrl: 'https://example.com/no-cover.jpg',
        ));
        // Debounce (0.5s) + the cubit's 5s palette timeout.
        await Future<void>.delayed(const Duration(milliseconds: 6500));
      });
      await tester.pump();
      tester.takeException();

      // A transient failure with nothing better to show intentionally leaves
      // the existing palette untouched rather than hard-resetting it.
      expect(states, isEmpty);
      expect(cubit.state.primaryColor, Colors.red);
      expect(cubit.state.hasCustomArtworkColor, isTrue);
    });

    testWidgets('a remote palette failure re-emits the last good palette',
        (tester) async {
      final cache = ArtworkLruCache();
      cache.put('AUDIO_880008', base64Decode(_pngBase64), persistToDisk: false);
      final cubit = DynamicThemeCubit();
      addTearDown(cubit.close);
      final states = <DynamicThemeState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      await tester.runAsync(() async {
        unawaited(cubit.updateFromDetails(songId: 880008));
        await Future<void>.delayed(const Duration(milliseconds: 2500));
      });
      await tester.pump();
      final goodPalette = states.last;
      expect(goodPalette.hasCustomArtworkColor, isTrue);

      await tester.runAsync(() async {
        unawaited(cubit.updateFromDetails(
          songId: 880009,
          remoteArtworkUrl: 'https://example.com/missing.jpg',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 6500));
      });
      await tester.pump();
      tester.takeException();

      expect(states.last.primaryColor, goodPalette.primaryColor);
      expect(states.last.secondaryColor, goodPalette.secondaryColor);
      expect(states.last.hasCustomArtworkColor, isTrue);
    });

    testWidgets('close cancels the pending debounce and further updates',
        (tester) async {
      final cache = ArtworkLruCache();
      cache.put('AUDIO_880010', base64Decode(_pngBase64), persistToDisk: false);
      final cubit = DynamicThemeCubit();
      final states = <DynamicThemeState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      unawaited(cubit.updateFromDetails(songId: 880010));
      await cubit.close();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(states, isEmpty);
      expect(cubit.activeTimerCount, 0);
    });
  });
}
