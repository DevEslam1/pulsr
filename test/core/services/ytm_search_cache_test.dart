// test/core/services/ytm_search_cache_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_search_cache.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

YtmTrack _track(String id, {String? title}) => YtmTrack(
      videoId: id,
      title: title ?? id,
      artist: 'Artist',
      duration: const Duration(minutes: 3),
      artworkUrl: 'https://art/$id.jpg',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('round-trips tracks for the same query, case-insensitively', () async {
    final cache = YtmSearchCache();
    await cache.write('Rick Astley', [_track('dQw4w9WgXcQ', title: 'Hit')]);

    final results = await cache.read(' rick astley ');

    expect(results, hasLength(1));
    expect(results.single.videoId, 'dQw4w9WgXcQ');
    expect(results.single.title, 'Hit');
    expect(results.single.artworkUrl, 'https://art/dQw4w9WgXcQ.jpg');
  });

  test('a rewrite for the same query replaces the older page', () async {
    final cache = YtmSearchCache();
    await cache.write('q', [_track('old')]);
    await cache.write('q', [_track('new1'), _track('new2')]);

    final results = await cache.read('q');

    expect(results.map((t) => t.videoId), ['new1', 'new2']);
    final stored = jsonDecode(
      (await SharedPreferences.getInstance())
          .getString(YtmSearchCache.prefsKey)!,
    ) as List;
    expect(stored, hasLength(1));
  });

  test('entries older than the TTL are ignored', () async {
    final cache = YtmSearchCache();
    final now = DateTime(2026, 1, 1);
    await cache.write('q', [_track('a')], now: now);

    expect(
      await cache.read('q', now: now.add(const Duration(days: 13))),
      hasLength(1),
    );
    expect(
      await cache.read('q', now: now.add(const Duration(days: 15))),
      isEmpty,
    );
  });

  test('bounds the number of stored queries', () async {
    final cache = YtmSearchCache();
    for (var i = 0; i < YtmSearchCache.maxEntries + 5; i++) {
      await cache.write('q$i', [_track('v$i')]);
    }

    final prefs = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(prefs.getString(YtmSearchCache.prefsKey)!) as List;

    expect(stored, hasLength(YtmSearchCache.maxEntries));
    expect(await cache.read('q0'), isEmpty);
    expect(await cache.read('q${YtmSearchCache.maxEntries + 4}'), hasLength(1));
  });

  test('bounds the results stored per query', () async {
    final cache = YtmSearchCache();
    await cache.write(
      'q',
      List.generate(
          YtmSearchCache.maxResultsPerEntry + 10, (i) => _track('v$i')),
    );

    expect(
      await cache.read('q'),
      hasLength(YtmSearchCache.maxResultsPerEntry),
    );
  });

  test('a corrupt payload is a cache miss, never a throw', () async {
    SharedPreferences.setMockInitialValues({
      YtmSearchCache.prefsKey: 'not json',
    });

    expect(await YtmSearchCache().read('q'), isEmpty);
  });

  test('empty results are not cached', () async {
    final cache = YtmSearchCache();
    await cache.write('q', const []);

    expect(await cache.read('q'), isEmpty);
  });
}
