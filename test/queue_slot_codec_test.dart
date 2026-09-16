import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/queue_slot_codec.dart';

SongsTableData song(
  int id, {
  String source = SongSource.local,
  String title = 'T',
}) {
  return SongsTableData(
    id: id,
    title: '$title $id',
    artist: 'A',
    album: 'B',
    durationMs: 200000,
    path: '/m/$id.mp3',
    source: source,
    remoteId: null,
    remoteArtworkUrl: null,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    lastPositionMs: 0,
  );
}

void main() {
  group('QueueSlotCodec', () {
    test('encodeDocument preserves slot structure and active slot', () {
      final doc = QueueSlotCodec.encodeDocument(
        {
          0: (
            songs: [song(1), song(2)],
            currentIndex: 1,
            position: const Duration(seconds: 30),
            speed: 1.25,
          ),
          1: (
            songs: [song(-5, source: SongSource.youtube, title: 'Y')],
            currentIndex: 0,
            position: Duration.zero,
            speed: 1.0,
          ),
        },
        1,
      );

      expect(doc['activeSlot'], 1);
      final s0 = doc['0'] as Map<String, dynamic>;
      expect(s0['songIds'], [1, 2]);
      expect(s0['currentIndex'], 1);
      expect(s0['positionMs'], 30000);
      expect(s0['speed'], 1.25);
      // Local songs are not duplicated into onlineSongs.
      expect((s0['onlineSongs'] as List), isEmpty);

      final s1 = doc['1'] as Map<String, dynamic>;
      expect(s1['songIds'], [-5]);
      final online = s1['onlineSongs'] as List;
      expect(online.length, 1);
      expect((online.first as Map<String, dynamic>)['title'], 'Y -5');
    });

    test('decodeDocument rejects non-maps and oversized documents', () {
      expect(QueueSlotCodec.decodeDocument(null), isNull);
      expect(QueueSlotCodec.decodeDocument([]), isNull);
      expect(QueueSlotCodec.decodeDocument({'a': 1}), isNotNull);
      expect(
        QueueSlotCodec.decodeDocument(
            {'0': 1, '1': 1, '2': 1, 'activeSlot': 1, 'extra': 1}),
        isNull,
      );
    });

    test('slotIndexForKey accepts only 0..2', () {
      expect(QueueSlotCodec.slotIndexForKey('0'), 0);
      expect(QueueSlotCodec.slotIndexForKey('2'), 2);
      expect(QueueSlotCodec.slotIndexForKey('3'), isNull);
      expect(QueueSlotCodec.slotIndexForKey('activeSlot'), isNull);
      expect(QueueSlotCodec.slotIndexForKey('x'), isNull);
    });

    test('decodeSlot rejects oversized and id-less payloads', () {
      expect(
        QueueSlotCodec.decodeSlot({'songIds': [1, 2]}, 500),
        isNotNull,
      );
      // Over the queue cap.
      expect(
        QueueSlotCodec.decodeSlot(
            {'songIds': List.generate(501, (i) => i)}, 500),
        isNull,
      );
      // No usable ids.
      expect(QueueSlotCodec.decodeSlot({'songIds': ['a', 1.5]}, 500), isNull);
      expect(QueueSlotCodec.decodeSlot({}, 500), isNull);
    });

    test('mergeInPersistedOrder restores playback order, db first', () {
      final db = {2: song(2), 1: song(1)};
      final online = {-9: song(-9, source: SongSource.youtube)};
      final merged =
          QueueSlotCodec.mergeInPersistedOrder([3, 1, -9, 2], db, online);
      // 3 matches nothing and is dropped; the rest keep persisted order.
      expect(merged.map((s) => s.id).toList(), [1, -9, 2]);
    });

    test('clamps keep restored values in safe ranges', () {
      expect(QueueSlotCodec.clampCurrentIndex(99, 3), 2);
      expect(QueueSlotCodec.clampCurrentIndex(-4, 3), 0);
      expect(QueueSlotCodec.clampPosition(9999999999).inMilliseconds,
          QueueSlotCodec.maxPositionMs);
      expect(QueueSlotCodec.clampSpeed(double.nan), 1.0);
      expect(QueueSlotCodec.clampSpeed(99.0), QueueSlotCodec.maxSpeed);
    });

    test('activeSlotFrom accepts only 0..2 ints', () {
      expect(QueueSlotCodec.activeSlotFrom(1), 1);
      expect(QueueSlotCodec.activeSlotFrom(5), isNull);
      expect(QueueSlotCodec.activeSlotFrom('1'), isNull);
      expect(QueueSlotCodec.activeSlotFrom(null), isNull);
    });
  });
}
