import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RadioStationStore.resetForTesting();
  });

  tearDown(() {
    RadioStationStore.resetForTesting();
  });

  group('RadioStationStore Singleton & Concurrency', () {
    test('is a true singleton across multiple instantiations', () {
      final store1 = RadioStationStore();
      final store2 = RadioStationStore();
      expect(identical(store1, store2), isTrue);
    });

    test(
        'concurrent add calls while loading resolve safely via mutex without dropping stations',
        () async {
      SharedPreferences.setMockInitialValues({
        RadioStationStore.prefsKey: jsonEncode([
          {
            'id': 'initial-1',
            'name': 'Initial Station',
            'url': 'https://example.com/stream1',
            'genre': 'Pop',
          }
        ]),
      });

      final store1 = RadioStationStore();
      final store2 = RadioStationStore();

      const newStationA = RadioStation(
        id: 'station-a',
        name: 'Station A',
        url: 'https://example.com/a',
        genre: 'Jazz',
      );
      const newStationB = RadioStation(
        id: 'station-b',
        name: 'Station B',
        url: 'https://example.com/b',
        genre: 'Quran',
      );

      // Concurrent adds without awaiting ready explicitly
      await Future.wait([
        store1.add(newStationA),
        store2.add(newStationB),
      ]);

      expect(store1.list.length, equals(3));
      final ids = store1.list.map((s) => s.id).toList();
      expect(ids, contains('station-a'));
      expect(ids, contains('station-b'));
      expect(ids, contains('initial-1'));

      // Station B is Quran, so it should be sorted first
      expect(store1.list.first.id, equals('station-b'));
    });

    test('replaces existing station without losing order or duplicating',
        () async {
      final store = RadioStationStore();
      await store.ready;

      const station = RadioStation(
        id: 'st-1',
        name: 'Original',
        url: 'https://example.com/live',
      );
      await store.add(station);

      const updated = RadioStation(
        id: 'st-1',
        name: 'Updated Name',
        url: 'https://example.com/live2',
      );
      final replaced = await store.replace(station, updated);
      expect(replaced, isTrue);
      expect(store.list.length, equals(1));
      expect(store.list.first.name, equals('Updated Name'));
      expect(store.list.first.url, equals('https://example.com/live2'));
    });

    test('does not match bare حصري as Hussary artwork or Quran station', () {
      const exclusiveStation = RadioStation(
        id: 'st-exclusive',
        name: 'بث حصري للأخبار',
        url: 'https://example.com/live-news',
      );

      expect(
        RadioStationStore.resolveArtworkForStation(
          id: exclusiveStation.id,
          name: exclusiveStation.name,
          url: exclusiveStation.url,
        ),
        isNull,
      );
      expect(
        RadioStationStore.resolveHomeCardForStation(
          id: exclusiveStation.id,
          name: exclusiveStation.name,
          url: exclusiveStation.url,
        ),
        isNull,
      );
      expect(RadioStationStore.isQuranStation(exclusiveStation), isFalse);

      const hussaryStation = RadioStation(
        id: 'st-hussary',
        name: 'الشيخ الحصري',
        url: 'https://example.com/recitation',
      );
      expect(
        RadioStationStore.resolveArtworkForStation(
          id: hussaryStation.id,
          name: hussaryStation.name,
          url: hussaryStation.url,
        ),
        equals(RadioStationStore.hussaryArtwork),
      );
      expect(
        RadioStationStore.resolveHomeCardForStation(
          id: hussaryStation.id,
          name: hussaryStation.name,
          url: hussaryStation.url,
        ),
        equals(RadioStationStore.hussaryHomeCard),
      );
      expect(RadioStationStore.isQuranStation(hussaryStation), isTrue);
    });

    test(
        'resolves curated cur-quran-tarteel artwork and retries after corrupt JSON load',
        () async {
      expect(
        RadioStationStore.resolveArtworkForStation(
          id: 'cur-quran-tarteel',
          name: 'إذاعة تراتيل قصيرة متميزة',
          url: 'https://example.com/tarteel',
        ),
        isNotNull,
      );

      SharedPreferences.setMockInitialValues({
        RadioStationStore.prefsKey: '{"not": "a list"}',
      });
      RadioStationStore.resetForTesting();
      final store = RadioStationStore();
      await store.ready;
      expect(store.loadFailed, isTrue);

      SharedPreferences.setMockInitialValues({
        RadioStationStore.prefsKey: jsonEncode([
          {
            'id': 'recovered-1',
            'name': 'Recovered',
            'url': 'https://example.com/ok',
          }
        ]),
      });
      await store.load();
      expect(store.loadFailed, isFalse);
      expect(store.list.single.id, 'recovered-1');
    });
  });
}
