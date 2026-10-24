// RadioStationStore batch/collision coverage: import persists once, replace is
// atomic and can never drop the old entry on a rejected update.
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

  test('addAll persists every station in one pass', () async {
    final store = RadioStationStore();
    await store.ready;
    final count = await store.addAll([
      RadioStation.create(name: 'A', url: 'https://a.example.com/live'),
      RadioStation.create(name: 'B', url: 'https://b.example.com/live'),
    ]);

    expect(count, 2);
    expect(store.list.length, 2);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(RadioStationStore.prefsKey);
    expect(raw, isNotNull);
    expect((jsonDecode(raw!) as List).length, 2);
  });

  test('addAll skips invalid URLs but persists the rest', () async {
    final store = RadioStationStore();
    await store.ready;
    final count = await store.addAll([
      RadioStation.create(name: 'A', url: 'https://a.example.com/live'),
      RadioStation.create(name: 'Bad', url: 'file:///etc/passwd'),
    ]);

    expect(count, 1);
    expect(store.list.single.url, 'https://a.example.com/live');
  });

  test('replace swaps entries atomically and keeps other stations', () async {
    final store = RadioStationStore();
    await store.ready;
    final oldStation =
        RadioStation.create(name: 'Old', url: 'https://old.example.com/live');
    final other = RadioStation.create(
        name: 'Other', url: 'https://other.example.com/live');
    await store.addAll([oldStation, other]);

    final updated =
        RadioStation.create(name: 'New', url: 'https://new.example.com/live');
    expect(await store.replace(oldStation, updated), isTrue);
    expect(store.list.any((s) => s.url == oldStation.url), isFalse);
    expect(store.list.any((s) => s.url == updated.url), isTrue);
    expect(store.list.any((s) => s.url == other.url), isTrue);
  });

  test('replace rejects an invalid URL without touching the list', () async {
    final store = RadioStationStore();
    await store.ready;
    final oldStation =
        RadioStation.create(name: 'Old', url: 'https://old.example.com/live');
    await store.add(oldStation);

    final invalid = RadioStation.create(name: 'Bad', url: 'file:///x');
    expect(await store.replace(oldStation, invalid), isFalse);
    expect(store.list.single.url, oldStation.url);
  });

  test('curated reciter stations carry their artwork assets', () async {
    final store = RadioStationStore();
    await store.ready;
    await store.importCurated();
    final byId = {for (final s in store.list) s.id: s};

    expect(byId['cur-quran-cairo']!.artworkUrl,
        RadioStationStore.quranCairoArtwork);
    expect(byId['cur-quran-cairo-backup']!.artworkUrl,
        RadioStationStore.quranCairoArtwork);
    expect(byId['cur-quran-minshawi']!.artworkUrl,
        RadioStationStore.minshawiArtwork);
    expect(byId['cur-quran-mustafa']!.artworkUrl,
        RadioStationStore.mustafaIsmailArtwork);
    expect(byId['cur-quran-abdulbasit']!.artworkUrl,
        RadioStationStore.abdulBasitArtwork);
  });

  test('loading a persisted curated station backfills missing artwork',
      () async {
    SharedPreferences.setMockInitialValues({
      RadioStationStore.prefsKey: jsonEncode([
        {
          'id': 'cur-quran-minshawi',
          'name': 'إذاعة الشيخ محمد صديق المنشاوي (مجود)',
          'url':
              'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi_mojawwad',
          'genre': 'Quran',
        },
      ]),
    });
    final store = RadioStationStore();
    await store.ready;

    expect(store.list.single.artworkUrl, RadioStationStore.minshawiArtwork);
  });

  test('hasUrlCollision can exclude the station being edited', () async {
    final store = RadioStationStore();
    await store.ready;
    final station =
        RadioStation.create(name: 'A', url: 'https://a.example.com/live');
    await store.add(station);

    expect(store.hasUrlCollision(station.url), isTrue);
    expect(store.hasUrlCollision(station.url, exceptId: station.id), isFalse);
    expect(store.hasUrlCollision('https://fresh.example.com/live'), isFalse);
  });
}
