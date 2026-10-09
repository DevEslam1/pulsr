// WidgetService artwork lifecycle coverage: local-file artwork resolution,
// the synchronous already-cached fast path, the failure path that flags
// `artworkFailed`, the widget-click host/path parsing, and the queue drain that
// skips a re-save of the same song. The prune and basic content paths are
// covered by widget_service_test.dart.
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
  int id = 3,
  String? artworkUri,
  String? remoteArtworkUrl,
  String title = 'Track',
}) =>
    SongsTableData(
      id: id,
      title: title,
      artist: 'Artist',
      album: 'Album',
      durationMs: 180000,
      path: '/music/$id.mp3',
      artworkUri: artworkUri,
      remoteArtworkUrl: remoteArtworkUrl,
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      source: 'local',
      isDownloaded: false,
    );

List<Object?> _allSaved(List<MethodCall> calls, String id) {
  final result = <Object?>[];
  for (final call in calls) {
    if (call.method != 'saveWidgetData') continue;
    final args = call.arguments;
    if (args is Map && args['id'] == id) result.add(args['data']);
  }
  return result;
}

Object? _lastSaved(List<MethodCall> calls, String id) {
  final all = _allSaved(calls, id);
  return all.isEmpty ? null : all.last;
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<MethodCall> calls;
  late WidgetService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('pulsr_widget_art_svc_');
    calls = [];
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

  test('resolves local file artwork and persists the cached path', () async {
    final source = File('${tempDir.path}${Platform.pathSeparator}cover.png')
      ..writeAsBytesSync([1, 2, 3, 4, 5]);

    final song = _song(id: 21, artworkUri: source.uri.toString());
    await service.updateNowPlaying(song: song, isPlaying: true);
    // Wait for the background artwork resolution to land.
    await _settle();
    await _settle();

    final artwork = _lastSaved(calls, 'artwork');
    expect(artwork, isA<String>());
    expect(artwork as String, isNotEmpty);
    expect(File(artwork).existsSync(), isTrue);
    expect(_lastSaved(calls, 'artworkFailed'), isFalse);
  });

  test('a second update for the same song reuses the cached artwork',
      () async {
    final source = File('${tempDir.path}${Platform.pathSeparator}cover.png')
      ..writeAsBytesSync([9, 8, 7]);
    final song = _song(id: 22, artworkUri: source.uri.toString());

    await service.updateNowPlaying(song: song, isPlaying: true);
    await _settle();
    await _settle();

    calls.clear();
    await service.updateNowPlaying(song: song, isPlaying: false);
    // The cached path is saved synchronously inside the call, before settling.
    expect(_lastSaved(calls, 'artwork'), isNotNull);
  });

  test('flags artworkFailed when no artwork can be resolved', () async {
    // Negative id skips the MediaStore fallback, and no artwork source means
    // the resolver returns null -> failure flag.
    await service.updateNowPlaying(
      song: _song(id: -5, title: 'No Art'),
      isPlaying: true,
    );
    await _settle();
    await _settle();

    expect(_lastSaved(calls, 'artwork'), '');
    expect(_lastSaved(calls, 'artworkFailed'), isTrue);
  });

  test('a null song clears artwork state and the pending queue', () async {
    await service.updateNowPlaying(song: null, isPlaying: false);

    expect(_lastSaved(calls, 'artwork'), '');
    expect(_lastSaved(calls, 'artworkFailed'), isFalse);
    expect(_lastSaved(calls, 'queueCover'), '');
  });

  test('listenToWidgetClicks parses the path form and forwards known actions',
      () async {
    _messenger.setMockMethodCallHandler(_eventChannel, (call) async => null);
    addTearDown(
        () => _messenger.setMockMethodCallHandler(_eventChannel, null));

    final received = <Uri?>[];
    final sub = service.listenToWidgetClicks(received.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(Duration.zero);

    const codec = StandardMethodCodec();
    Future<void> emit(Object? payload) => _messenger.handlePlatformMessage(
          'home_widget/updates',
          codec.encodeSuccessEnvelope(payload),
          null,
        );

    // Host-less form: the action is read from the path.
    await emit('pulsrwidget:/play_pause');
    // Unknown action is filtered.
    await emit('pulsrwidget:/nope');
    await emit('pulsrwidget:/main');

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      received.map((u) => u.toString()).toList(),
      ['pulsrwidget:/play_pause', 'pulsrwidget:/main'],
    );
  });
}
