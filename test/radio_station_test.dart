import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/domain/models/radio_station.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RadioStation', () {
    test('round-trips through JSON', () {
      final station = RadioStation.create(
        name: 'Jazz FM',
        url: 'https://example.com/live.m3u8',
        genre: 'Jazz',
        artworkUrl: 'https://example.com/art.png',
        lastPlayed: 123456,
      );

      final restored = RadioStation.fromJson(station.toJson());

      expect(restored.id, station.id);
      expect(restored.name, 'Jazz FM');
      expect(restored.url, 'https://example.com/live.m3u8');
      expect(restored.genre, 'Jazz');
      expect(restored.artworkUrl, 'https://example.com/art.png');
      expect(restored.lastPlayed, 123456);
    });

    test('derives a stable id from the url', () {
      final a = RadioStation.create(name: 'One', url: 'https://a.com/live');
      final b = RadioStation.create(name: 'Two', url: 'https://a.com/live');
      expect(a.id, b.id);
    });

    test('songId is a negative, stable pseudo-song id', () {
      final a = RadioStation.create(name: 'One', url: 'https://a.com/live');
      final b = RadioStation.create(name: 'Two', url: 'https://a.com/live');
      expect(a.songId, lessThan(0));
      expect(a.songId, b.songId);
    });

    test('classifies http/https urls and rejects everything else', () {
      expect(RadioStation.isHttpUrl('http://a.com/live'), isTrue);
      expect(RadioStation.isHttpUrl('https://a.com:8000/live'), isTrue);
      expect(RadioStation.isHttpUrl('HTTPS://A.COM/live'), isTrue);
      expect(RadioStation.isHttpUrl('file:///music/a.mp3'), isFalse);
      expect(RadioStation.isHttpUrl('ftp://a.com/live'), isFalse);
      expect(RadioStation.isHttpUrl('/music/a.mp3'), isFalse);
      expect(RadioStation.isHttpUrl(r'C:\music\a.mp3'), isFalse);
      expect(RadioStation.isHttpUrl('ytmusic://abc'), isFalse);
      expect(RadioStation.isHttpUrl('http://'), isFalse);
      expect(RadioStation.isHttpUrl(''), isFalse);
    });
  });

  group('RadioStationStore', () {
    test('add/list/remove behavior and persistence', () async {
      final store = RadioStationStore();
      await store.ready;
      expect(store.list, isEmpty);

      final station =
          RadioStation.create(name: 'A', url: 'https://a.com/live');
      await store.add(station);
      expect(store.list.length, 1);
      expect(store.list.first.name, 'A');
      expect(store.list.first.url, 'https://a.com/live');

      final reloaded = RadioStationStore();
      await reloaded.ready;
      expect(reloaded.list.length, 1);
      expect(reloaded.list.first.url, 'https://a.com/live');

      await store.remove(station.id);
      expect(store.list, isEmpty);

      final reloadedAfterRemove = RadioStationStore();
      await reloadedAfterRemove.ready;
      expect(reloadedAfterRemove.list, isEmpty);
    });

    test('rejects stations whose url is not http(s)', () async {
      final store = RadioStationStore();
      await store.ready;
      await store.add(RadioStation.create(name: 'Bad', url: '/local/a.mp3'));
      await store.add(RadioStation.create(name: 'Also bad', url: 'ftp://a/x'));
      expect(store.list, isEmpty);
    });

    test('re-adding the same url replaces instead of duplicating', () async {
      final store = RadioStationStore();
      await store.ready;
      await store.add(RadioStation.create(name: 'Old', url: 'https://a.com/live'));
      await store.add(RadioStation.create(name: 'New', url: 'https://a.com/live'));
      expect(store.list.length, 1);
      expect(store.list.first.name, 'New');
    });

    test('markPlayed updates lastPlayed and persists', () async {
      final store = RadioStationStore();
      await store.ready;
      final station =
          RadioStation.create(name: 'A', url: 'https://a.com/live');
      await store.add(station);
      await store.markPlayed(station.id, 999);

      final reloaded = RadioStationStore();
      await reloaded.ready;
      expect(reloaded.list.first.lastPlayed, 999);
    });

    test('importCurated adds the directory once and is idempotent', () async {
      final store = RadioStationStore();
      await store.ready;
      expect(store.list, isEmpty);

      final curatedCount = RadioStationStore.curatedDirectory().length;
      final added = await store.importCurated();
      expect(added, curatedCount);
      expect(store.list.length, curatedCount);

      // Second import must not duplicate.
      final addedAgain = await store.importCurated();
      expect(addedAgain, 0);
      expect(store.list.length, curatedCount);

      // Persisted for the next session.
      final reloaded = RadioStationStore();
      await reloaded.ready;
      expect(reloaded.list.length, curatedCount);
    });
  });

  group('RadioStationStore.extractStreamUrls', () {
    test('extracts absolute http(s) urls and ignores the rest', () {
      const content = '#EXTM3U\n'
          '#EXTINF:-1,Jazz\n'
          'https://a.com/live.m3u8\n'
          'http://b.com:8000/stream\n'
          '/local/file.mp3\n'
          r'C:\music\a.mp3'
          '\n'
          '# another comment\n'
          '"https://c.com/quoted"\n'
          '\n';

      expect(
        RadioStationStore.extractStreamUrls(content),
        [
          'https://a.com/live.m3u8',
          'http://b.com:8000/stream',
          'https://c.com/quoted',
        ],
      );
    });

    test('deduplicates repeated urls', () {
      const content = 'https://a.com/live\nhttps://a.com/live\n';
      expect(RadioStationStore.extractStreamUrls(content),
          ['https://a.com/live']);
    });
  });
}
