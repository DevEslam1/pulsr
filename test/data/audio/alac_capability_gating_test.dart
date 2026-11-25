import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/data/audio/decoder_runtime_probe.dart';
import 'package:pulsr/data/audio/format_aware_decoder.dart';
import 'package:pulsr/data/db/app_database.dart';

SongsTableData _song({
  required String path,
  String? codec,
  int? sampleRate,
}) =>
    SongsTableData(
      id: 1,
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      durationMs: 60000,
      path: path,
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      isDownloaded: false,
      codec: codec,
      sampleRate: sampleRate,
    );

void main() {
  test('M4A holding ALAC is refused when the platform has no decoder',
      () async {
    final probes = <String>[];
    final decoder = FormatAwareDecoder(
      resolveYtmStream: (song, tag) async =>
          AudioSource.uri(Uri.parse('https://example.com')),
      decoderProbe: DecoderRuntimeProbe(probe: (mime, rate) async {
        probes.add('$mime@$rate');
        return false;
      }),
    );

    await expectLater(
      decoder.decodeForFormat(
        _song(path: '/music/track.m4a', codec: 'ALAC', sampleRate: 96000),
        const MediaItem(id: '1', title: 'Track'),
      ),
      throwsA(isA<PlayerException>()
          .having((e) => e.code, 'code', 9003)
          .having((e) => e.message, 'message', contains('ALAC'))),
    );
    expect(probes, isNotEmpty);
    expect(probes.first, 'audio/alac@96000');
  });

  test('M4A holding ALAC plays when the platform advertises a decoder',
      () async {
    final decoder = FormatAwareDecoder(
      resolveYtmStream: (song, tag) async =>
          AudioSource.uri(Uri.parse('https://example.com')),
      decoderProbe: DecoderRuntimeProbe(probe: (mime, rate) async => true),
    );

    final source = await decoder.decodeForFormat(
      _song(path: '/music/track.m4a', codec: 'ALAC', sampleRate: 44100),
      const MediaItem(id: '1', title: 'Track'),
    );
    expect(source, isNotNull);
  });

  test('AAC in M4A does not consult the ALAC probe', () async {
    var probed = false;
    final decoder = FormatAwareDecoder(
      resolveYtmStream: (song, tag) async =>
          AudioSource.uri(Uri.parse('https://example.com')),
      decoderProbe: DecoderRuntimeProbe(probe: (mime, rate) async {
        probed = true;
        return false;
      }),
    );

    final source = await decoder.decodeForFormat(
      _song(path: '/music/track.m4a', codec: 'AAC', sampleRate: 44100),
      const MediaItem(id: '1', title: 'Track'),
    );
    expect(source, isNotNull);
    expect(probed, isFalse);
  });

  test('.alac extension is gated by the same runtime decoder check', () async {
    final decoder = FormatAwareDecoder(
      resolveYtmStream: (song, tag) async =>
          AudioSource.uri(Uri.parse('https://example.com')),
      decoderProbe: DecoderRuntimeProbe(probe: (mime, rate) async => false),
    );

    await expectLater(
      decoder.decodeForFormat(
        _song(path: '/music/track.alac', codec: 'ALAC'),
        const MediaItem(id: '1', title: 'Track'),
      ),
      throwsA(isA<PlayerException>().having((e) => e.code, 'code', 9003)),
    );
  });

  test('runtime probe caches by MIME and sample rate', () async {
    var calls = 0;
    final probe = DecoderRuntimeProbe(probe: (mime, rate) async {
      calls++;
      return true;
    });

    expect(await probe.supports('audio/alac', sampleRate: 44100), isTrue);
    expect(await probe.supports('AUDIO/ALAC', sampleRate: 44100), isTrue);
    expect(await probe.supports('audio/alac', sampleRate: 96000), isTrue);
    expect(calls, 2);
  });
}
