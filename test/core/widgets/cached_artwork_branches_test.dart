// CachedArtwork / ArtworkLruCache branch coverage.
//
// Exercises the LRU store (insert, eviction, weak large payloads, trimming),
// the high-res URL upgrader, invalidation, and the widget's remote fetch paths
// (file://, bare file path and HTTPS via a fake HttpClient).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/artwork_placeholder.dart';
import 'package:pulsr/core/widgets/cached_artwork.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

// ---------------------------------------------------------------------------
// Minimal HttpClient fake for the HTTPS artwork path.
// ---------------------------------------------------------------------------

class _Headers implements HttpHeaders {
  final Map<String, String> values = {};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final List<int> body;
  final int? fixedLength;
  final _Headers _headers = _Headers();

  _Response({required this.statusCode, this.body = const [], this.fixedLength});

  @override
  int get contentLength => fixedLength ?? body.length;

  @override
  HttpHeaders get headers => _headers;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(body).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Request implements HttpClientRequest {
  @override
  final Uri uri;
  final Future<_Response> Function(_Request) onClose;
  _Request(this.uri, this.onClose);
  @override
  Future<HttpClientResponse> close() => onClose(this);
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeClient implements HttpClient {
  final Future<_Response> Function(_Request) handler;
  final List<Uri> requested = [];
  _FakeClient(this.handler);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requested.add(url);
    return _Request(url, handler);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

Uint8List _png() => Uint8List.fromList([
      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
      0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 213, 196, 200, 0, 0, 0, 13, 73, 68, 65,
      84, 120, 156, 99, 96, 248, 15, 0, 1, 5, 1, 2, 162, 162, 190, 253, 0, 0,
      0, 0, 73, 69, 78, 68, 174, 66, 96, 130
    ]);

Widget _wrap(Widget child) => MaterialApp(
      theme: AuraTheme.customTheme(const Color(0xFF9B9EF5),
          brightness: Brightness.dark),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArtworkLruCache', () {
    test('stores, refreshes and removes entries', () {
      final cache = ArtworkLruCache.withCapacity(10);
      final bytes = _png();
      cache.put('k1', bytes, persistToDisk: false);

      expect(cache.containsKey('k1'), isTrue);
      expect(cache.get('k1'), same(bytes));
      expect(cache.currentBytes, bytes.length);
      expect(cache.length, 1);

      cache.remove('k1');
      expect(cache.containsKey('k1'), isFalse);
      expect(cache.currentBytes, 0);

      cache.put('k2', bytes, persistToDisk: false);
      cache.clear();
      expect(cache.length, 0);
      expect(cache.currentBytes, 0);
    });

    test('null and empty payloads evict the key', () {
      final cache = ArtworkLruCache.withCapacity(5);
      cache.put('k', _png(), persistToDisk: false);
      cache.put('k', null, persistToDisk: false);
      expect(cache.containsKey('k'), isFalse);

      cache.put('k', Uint8List(0), persistToDisk: false);
      expect(cache.containsKey('k'), isFalse);
    });

    test('payloads larger than the cache budget are rejected', () {
      final cache = ArtworkLruCache.withCapacity(5);
      final tooBig = Uint8List(ArtworkLruCache.maxBytes + 1);
      cache.put('huge', tooBig, persistToDisk: false);
      expect(cache.containsKey('huge'), isFalse);
      expect(cache.currentBytes, 0);
    });

    test('large payloads are held weakly and re-insertion does not leak', () {
      final cache = ArtworkLruCache.withCapacity(2);
      final large = Uint8List(ArtworkLruCache.largePayloadThreshold + 1);
      cache.put('big', large, persistToDisk: false);
      expect(cache.containsKey('big'), isTrue);
      // Re-insert the same key: the previous weak entry is swept first.
      cache.put('big', large, persistToDisk: false);
      expect(cache.length, 1);
    });

    test('evicts the oldest entry once the count cap is reached', () {
      final cache = ArtworkLruCache.withCapacity(2);
      final bytes = _png();
      cache.put('a', bytes, persistToDisk: false);
      cache.put('b', bytes, persistToDisk: false);
      cache.put('c', bytes, persistToDisk: false);

      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
      expect(cache.containsKey('c'), isTrue);
      expect(cache.length, 2);
    });

    test('trimForMemoryPressure clears weak entries and evicts down to half',
        () {
      final cache = ArtworkLruCache.withCapacity(4);
      final bytes = _png();
      for (final key in ['1', '2', '3', '4']) {
        cache.put(key, bytes, persistToDisk: false);
      }
      cache.put('big', Uint8List(ArtworkLruCache.largePayloadThreshold + 1),
          persistToDisk: false);
      expect(cache.length, 5);

      cache.trimForMemoryPressure();
      expect(cache.length, lessThanOrEqualTo(2));
    });

    test('get on a missing key returns null', () {
      final cache = ArtworkLruCache.withCapacity(2);
      expect(cache.get('missing'), isNull);
    });
  });

  group('upgradeToHighResArtwork', () {
    test('upgrades googleusercontent and ggpht sizing params', () {
      expect(
        CachedArtwork.upgradeToHighResArtwork(
            'https://lh3.googleusercontent.com/a=w100-h100-l90'),
        contains('=s1200'),
      );
      expect(
        CachedArtwork.upgradeToHighResArtwork(
            'https://lh3.ggpht.com/a=s200-c'),
        contains('=s1200'),
      );
    });

    test('upgrades YouTube thumbnail variants', () {
      expect(
        CachedArtwork.upgradeToHighResArtwork(
            'https://i.ytimg.com/vi/x/default.jpg'),
        contains('maxresdefault.jpg'),
      );
      expect(
        CachedArtwork.upgradeToHighResArtwork(
            'https://img.youtube.com/vi/x/hq720.jpg'),
        contains('maxresdefault.jpg'),
      );
    });

    test('leaves unrelated URLs untouched', () {
      const url = 'https://example.com/cover.png';
      expect(CachedArtwork.upgradeToHighResArtwork(url), url);
    });
  });

  group('invalidate', () {
    test('drops cached tiers and bumps the invalidation revision', () async {
      final before = ArtworkInvalidationBus.revision.value;
      ArtworkLruCache()
          .put('${ArtworkType.ALBUM.name}_4242', _png(), persistToDisk: false);

      await CachedArtwork.invalidate(id: 4242, type: ArtworkType.ALBUM);

      expect(ArtworkLruCache().containsKey('${ArtworkType.ALBUM.name}_4242'),
          isFalse);
      expect(ArtworkInvalidationBus.revision.value, greaterThan(before));
    });
  });

  group('CachedArtwork widget', () {
    late Directory tempDir;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('pulsr_art_cache_');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });
    tearDown(() async {
      await getIt.reset();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<void> pumpRealAsync(WidgetTester tester, Widget widget) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(widget);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump();
    }

    testWidgets('renders the placeholder when nothing can be resolved',
        (tester) async {
      await tester.pumpWidget(_wrap(const CachedArtwork(id: 0)));
      await tester.pumpAndSettle();
      expect(find.byType(ArtworkPlaceholder), findsOneWidget);
    });

    testWidgets('loads a file:// remote URL', (tester) async {
      final dir = Directory.systemTemp.createTempSync('pulsr_art_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/cover.png')..writeAsBytesSync(_png());

      await pumpRealAsync(
        tester,
        _wrap(CachedArtwork(
          id: 0,
          remoteUrl: Uri.file(file.path).toString(),
          size: 64,
        )),
      );

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('loads a bare filesystem path as a remote URL', (tester) async {
      final dir = Directory.systemTemp.createTempSync('pulsr_art_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/cover.png')..writeAsBytesSync(_png());

      await pumpRealAsync(
        tester,
        _wrap(CachedArtwork(
          id: 0,
          remoteUrl: file.path,
          size: 64,
        )),
      );

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('fetches HTTPS artwork through the shared HttpClient',
        (tester) async {
      getIt.registerSingleton<HttpClient>(
          _FakeClient((_) async => _Response(statusCode: 200, body: _png())));

      await pumpRealAsync(
        tester,
        _wrap(const CachedArtwork(
          id: 0,
          remoteUrl: 'https://example.com/cover.jpg',
          size: 64,
        )),
      );

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('falls back through YouTube thumbnail candidates',
        (tester) async {
      getIt.registerSingleton<HttpClient>(_FakeClient((request) async {
        if (request.uri.path.contains('maxresdefault')) {
          return _Response(statusCode: 404);
        }
        return _Response(statusCode: 200, body: _png());
      }));

      await pumpRealAsync(
        tester,
        _wrap(const CachedArtwork(
          id: 0,
          remoteUrl: 'https://i.ytimg.com/vi/x/hqdefault.jpg',
          highQuality: true,
          size: 300,
        )),
      );

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('rejects an oversized declared content length', (tester) async {
      getIt.registerSingleton<HttpClient>(_FakeClient((_) async => _Response(
            statusCode: 200,
            body: _png(),
            fixedLength: 11 * 1024 * 1024,
          )));

      await pumpRealAsync(
        tester,
        _wrap(const CachedArtwork(
          id: 0,
          remoteUrl: 'https://example.com/huge.jpg',
          size: 64,
        )),
      );

      expect(find.byType(ArtworkPlaceholder), findsOneWidget);
    });

    testWidgets('survives a network failure and shows the placeholder',
        (tester) async {
      getIt.registerSingleton<HttpClient>(
          _FakeClient((_) async => throw const SocketException('down')));

      await pumpRealAsync(
        tester,
        _wrap(const CachedArtwork(
          id: 0,
          remoteUrl: 'https://example.com/err.jpg',
          size: 64,
        )),
      );

      expect(find.byType(ArtworkPlaceholder), findsOneWidget);
    });

    testWidgets('reloads when the widget identity changes', (tester) async {
      final cache = ArtworkLruCache.withCapacity(4);
      cache.put('AUDIO_11', _png(), persistToDisk: false);

      await tester.pumpWidget(_wrap(CachedArtwork(
        id: 10,
        customCache: cache,
        size: 64,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(ArtworkPlaceholder), findsOneWidget);

      await tester.pumpWidget(_wrap(CachedArtwork(
        id: 11,
        customCache: cache,
        size: 64,
      )));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('handles unbounded size and infinite border radius',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: CachedArtwork(
                id: 0,
                size: double.infinity,
                borderRadius: double.infinity,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CachedArtwork), findsOneWidget);
    });
  });
}
