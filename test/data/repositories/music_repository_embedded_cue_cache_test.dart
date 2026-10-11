// test/data/repositories/music_repository_embedded_cue_cache_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';

const _siblingCue = '''
TITLE "Sibling Album"
FILE "album.flac" FLAC
  TRACK 01 AUDIO
    TITLE "One"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Two"
    INDEX 01 03:00:00
''';

const _embeddedCue = '''
TITLE "Embedded Album"
FILE "album.flac" FLAC
  TRACK 01 AUDIO
    TITLE "One"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Two"
    INDEX 01 03:00:00
''';

List<int> _le32(int value) => <int>[
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];

/// FLAC metadata block with a Vorbis comment holding `CUESHEET=<cue>`.
List<int> _flacWithVorbisCue(String cue) {
  final vendor = utf8.encode('unit-test');
  final comment = utf8.encode('CUESHEET=$cue');
  final vorbis = <int>[];
  vorbis.addAll(_le32(vendor.length));
  vorbis.addAll(vendor);
  vorbis.addAll(_le32(1));
  vorbis.addAll(_le32(comment.length));
  vorbis.addAll(comment);

  final out = <int>[...utf8.encode('fLaC')];
  out.add(0x80 | 4); // last block, type 4 (VORBIS_COMMENT)
  out.addAll(<int>[
    (vorbis.length >> 16) & 0xFF,
    (vorbis.length >> 8) & 0xFF,
    vorbis.length & 0xFF,
  ]);
  out.addAll(vorbis);
  return out;
}

void main() {
  late AppDatabase db;
  late MusicRepository repo;
  late Directory tempDir;

  setUp(() async {
    MusicRepository.resetEmbeddedCueProbeState();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MusicRepository(db);
    tempDir = await Directory.systemTemp.createTemp('pulsr_embedded_cue_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> containerFile(String name, List<int> bytes) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> insertContainer(String path) async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: const Value(10),
          title: 'Full Album',
          path: path,
          durationMs: const Value(600000),
        ));
  }

  test('sibling .cue wins and never probes the audio file', () async {
    final audio = await containerFile('album.flac', utf8.encode('x'));
    await containerFile('album.cue', utf8.encode(_siblingCue));

    await insertContainer(audio.path);

    expect((await repo.expandCueSheets()).getOrElse((_) => -1), 2);
    expect(MusicRepository.embeddedCueProbeCount, 0);

    expect((await repo.expandCueSheets()).getOrElse((_) => -1), 2);
    expect(MusicRepository.embeddedCueProbeCount, 0);
  });

  test('repeated syncs probe a cue-less file only once', () async {
    final audio = await containerFile('plain.flac', utf8.encode('not-audio'));

    await insertContainer(audio.path);

    expect((await repo.expandCueSheets()).getOrElse((_) => -1), 0);
    expect(MusicRepository.embeddedCueProbeCount, 1);

    expect((await repo.expandCueSheets()).getOrElse((_) => -1), 0);
    expect(MusicRepository.embeddedCueProbeCount, 1,
        reason: 'the negative cache must stop re-probing on every rescan');

    expect((await repo.expandCueSheets()).getOrElse((_) => -1), 0);
    expect(MusicRepository.embeddedCueProbeCount, 1);
  });

  test('embedded cue still expands and stays idempotent across syncs',
      () async {
    final audio =
        await containerFile('album.flac', _flacWithVorbisCue(_embeddedCue));

    await insertContainer(audio.path);

    expect((await repo.expandCueSheets()).getOrElse((_) => -1), 2);
    expect(MusicRepository.embeddedCueProbeCount, 1);

    final all = await db.select(db.songsTable).get();
    expect(all.where((s) => s.cueStartMs != null).length, 2);
    final container = all.firstWhere((s) => s.id == 10);
    expect(container.cueFile, 'embedded://${audio.path}');

    expect((await repo.expandCueSheets()).getOrElse((_) => -1), 2);
    final after = await db.select(db.songsTable).get();
    expect(after.where((s) => s.cueStartMs != null).length, 2,
        reason: 're-sync must not duplicate or drop virtual rows');
  });
}
