import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/widgets/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _homeWidgetChannel = MethodChannel('home_widget');
const MethodChannel _eventChannel = MethodChannel('home_widget/updates');
const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

SongsTableData _song({
  int id = 1,
  String title = 'Test Song',
  String artist = 'Test Artist',
  String album = 'Test Album',
  String path = '/music/test.mp3',
}) {
  return SongsTableData(
    id: id,
    title: title,
    artist: artist,
    album: album,
    durationMs: 180000,
    path: path,
    isFavorite: false,
    isMissing: false,
    playCount: 0,
    lastPositionMs: 0,
    source: 'local',
    isDownloaded: false,
  );
}

Object? _saved(List<MethodCall> calls, String id) {
  for (final call in calls.reversed) {
    if (call.method != 'saveWidgetData') continue;
    final args = call.arguments;
    if (args is Map && args['id'] == id) return args['data'];
  }
  return null;
}

List<Object?> _allSaved(List<MethodCall> calls, String id) {
  final result = <Object?>[];
  for (final call in calls) {
    if (call.method != 'saveWidgetData') continue;
    final args = call.arguments;
    if (args is Map && args['id'] == id) result.add(args['data']);
  }
  return result;
}

bool _updateWidgetCalled(List<MethodCall> calls) =>
    calls.any((c) => c.method == 'updateWidget');

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetService.pruneOldWidgetArtwork', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pulsr_widget_prune_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    File writeArt(String name, DateTime modified, {List<int> bytes = const [1, 2, 3]}) {
      final f = File('${tempDir.path}${Platform.pathSeparator}$name');
      f.writeAsBytesSync(bytes);
      f.setLastModifiedSync(modified);
      return f;
    }

    test('deletes files older than 7 days and keeps fresh + unrelated files',
        () async {
      final service = WidgetService();
      final now = DateTime.now();

      final veryOld = writeArt('pulsr_widget_art_old.png', now.subtract(const Duration(days: 30)));
      final justStale =
          writeArt('pulsr_widget_art_stale.png', now.subtract(const Duration(days: 8)));
      final boundary = writeArt('pulsr_widget_art_7d.png', now.subtract(const Duration(days: 7)));
      final fresh = writeArt('pulsr_widget_art_fresh.png', now.subtract(const Duration(hours: 3)));
      final unrelated = writeArt('unrelated.png', now.subtract(const Duration(days: 90)));

      await service.pruneOldWidgetArtwork(tempDir);

      expect(veryOld.existsSync(), isFalse);
      expect(justStale.existsSync(), isFalse);
      // Exactly 7 days old is NOT stale (strict `> 7`).
      expect(boundary.existsSync(), isTrue);
      expect(fresh.existsSync(), isTrue);
      // Files without the pattern prefix are never touched.
      expect(unrelated.existsSync(), isTrue);
    });

    test('caps survivors at 50, evicting the oldest first', () async {
      final service = WidgetService();
      final now = DateTime.now();

      final files = <File>[];
      for (var i = 0; i < 60; i++) {
        // All within the 7-day window, but file 0 is the oldest.
        files.add(writeArt(
          'pulsr_widget_art_$i.png',
          now.subtract(Duration(hours: 60 - i)),
        ));
      }

      await service.pruneOldWidgetArtwork(tempDir);

      final remaining = files.where((f) => f.existsSync()).toList();
      expect(remaining.length, 50);
      // The 10 oldest (indices 0..9) were evicted.
      for (var i = 0; i < 10; i++) {
        expect(files[i].existsSync(), isFalse, reason: 'file $i should be pruned');
      }
      for (var i = 10; i < 60; i++) {
        expect(files[i].existsSync(), isTrue, reason: 'file $i should survive');
      }
    });

    test('scans the dedicated pulsr_widget_art subdirectory when present',
        () async {
      final service = WidgetService();
      final now = DateTime.now();

      final subDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}pulsr_widget_art');
      subDir.createSync(recursive: true);

      final inSub = File(
          '${subDir.path}${Platform.pathSeparator}pulsr_widget_art_sub.png')
        ..writeAsBytesSync([1, 2, 3])
        ..setLastModifiedSync(now.subtract(const Duration(days: 20)));
      final inRoot = writeArt(
          'pulsr_widget_art_root.png', now.subtract(const Duration(days: 20)));

      await service.pruneOldWidgetArtwork(tempDir);

      expect(inSub.existsSync(), isFalse);
      // Root files are ignored once the dedicated subdirectory exists.
      expect(inRoot.existsSync(), isTrue);
    });

    test('is a no-op for an empty directory', () async {
      final service = WidgetService();
      await service.pruneOldWidgetArtwork(tempDir);
      expect(tempDir.listSync(), isEmpty);
    });
  });

  group('WidgetService.updateNowPlaying', () {
    late Directory tempDir;
    late List<MethodCall> calls;
    late WidgetService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      calls = [];
      tempDir = Directory.systemTemp.createTempSync('pulsr_widget_svc_');
      service = WidgetService();

      _messenger.setMockMethodCallHandler(_homeWidgetChannel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'saveWidgetData':
          case 'updateWidget':
          case 'setAppGroupId':
            return true;
          default:
            return null;
        }
      });
      _messenger.setMockMethodCallHandler(_pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      });
    });

    tearDown(() async {
      _messenger.setMockMethodCallHandler(_homeWidgetChannel, null);
      _messenger.setMockMethodCallHandler(_pathProviderChannel, null);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('saves full now-playing content for a song', () async {
      await service.updateNowPlaying(
        song: _song(id: 7, title: 'My Track', artist: 'The Artist', album: 'The Album'),
        isPlaying: true,
        position: const Duration(seconds: 30),
        duration: const Duration(minutes: 3),
        isFavorite: true,
        isShuffle: true,
        repeatMode: 'all',
        nextQueueTitles: const ['Up One', 'Up Two'],
        queueCover: 'cover-art',
      );
      await _settle();

      expect(_saved(calls, 'title'), 'My Track');
      expect(_saved(calls, 'artist'), 'The Artist');
      expect(_saved(calls, 'album'), 'The Album');
      expect(_saved(calls, 'isPlaying'), isTrue);
      expect(_saved(calls, 'isFavorite'), isTrue);
      expect(_saved(calls, 'isShuffle'), isTrue);
      expect(_saved(calls, 'repeatMode'), 'all');
      expect(_saved(calls, 'positionMs'), 30000);
      expect(_saved(calls, 'durationMs'), 180000);
      expect(_saved(calls, 'nextTrack0'), 'Up One');
      expect(_saved(calls, 'nextTrack1'), 'Up Two');
      expect(_saved(calls, 'nextTrack2'), '');
      expect(_saved(calls, 'upNext'), 'Up One');
      expect(_saved(calls, 'queueCover'), 'cover-art');
      expect(_allSaved(calls, 'contentVersion'), contains(1));
      expect(_updateWidgetCalled(calls), isTrue);
    });

    test('falls back to placeholder metadata for a null song', () async {
      await service.updateNowPlaying(song: null, isPlaying: false);

      expect(_saved(calls, 'title'), 'Pulsr Music');
      expect(_saved(calls, 'artist'), 'Nothing playing');
      expect(_saved(calls, 'album'), '');
      expect(_saved(calls, 'isPlaying'), isFalse);
      expect(_saved(calls, 'positionMs'), 0);
      expect(_saved(calls, 'durationMs'), 0);
      expect(_saved(calls, 'nextTrack0'), '');
      expect(_saved(calls, 'nextTrack1'), '');
      expect(_saved(calls, 'nextTrack2'), '');
      expect(_saved(calls, 'upNext'), '');
      expect(_saved(calls, 'queueCover'), '');
      expect(_saved(calls, 'artwork'), '');
      expect(_saved(calls, 'artworkFailed'), isFalse);
      expect(_updateWidgetCalled(calls), isTrue);
    });

    test('uses Pulsr Music titles when song metadata is blank', () async {
      await service.updateNowPlaying(
        song: _song(title: '   ', artist: '', album: 'Unknown Album'),
        isPlaying: true,
      );
      await _settle();

      expect(_saved(calls, 'title'), 'Pulsr Music');
      expect(_saved(calls, 'artist'), 'Nothing playing');
      expect(_saved(calls, 'album'), '');
    });
  });

  group('WidgetService.updateProgress', () {
    late List<MethodCall> calls;
    late WidgetService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      calls = [];
      service = WidgetService();
      _messenger.setMockMethodCallHandler(_homeWidgetChannel, (call) async {
        calls.add(call);
        return true;
      });
    });

    tearDown(() {
      _messenger.setMockMethodCallHandler(_homeWidgetChannel, null);
    });

    test('saves only playback progress and triggers a widget update', () async {
      await service.updateProgress(
        isPlaying: true,
        position: const Duration(seconds: 12, milliseconds: 500),
        duration: const Duration(minutes: 1),
      );

      expect(_saved(calls, 'isPlaying'), isTrue);
      expect(_saved(calls, 'positionMs'), 12500);
      expect(_saved(calls, 'durationMs'), 60000);
      expect(_saved(calls, 'title'), isNull);
      expect(_updateWidgetCalled(calls), isTrue);
    });
  });

  group('WidgetService.listenToWidgetClicks', () {
    setUp(() {
      _messenger.setMockMethodCallHandler(_eventChannel, (call) async => null);
    });

    tearDown(() {
      _messenger.setMockMethodCallHandler(_eventChannel, null);
    });

    Future<void> emit(Object? payload) {
      const codec = StandardMethodCodec();
      return _messenger.handlePlatformMessage(
        'home_widget/updates',
        codec.encodeSuccessEnvelope(payload),
        null,
      );
    }

    test('forwards known actions and filters invalid scheme / unknown actions',
        () async {
      final service = WidgetService();
      final received = <Uri?>[];
      final sub = service.listenToWidgetClicks(received.add);
      addTearDown(sub.cancel);

      // Let the EventChannel's `listen` round-trip complete.
      await Future<void>.delayed(Duration.zero);

      await emit('pulsrwidget://play_pause');
      await emit('https://example.com/next'); // wrong scheme
      await emit('pulsrwidget://definitely_not_known'); // unknown action
      await emit('pulsrwidget://next');
      await emit(null); // null payload
      await emit('pulsrwidget://favorite');

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        received.map((u) => u.toString()).toList(),
        ['pulsrwidget://play_pause', 'pulsrwidget://next', 'pulsrwidget://favorite'],
      );
    });
  });
}
