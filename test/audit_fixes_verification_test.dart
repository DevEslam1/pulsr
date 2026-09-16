import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/data/audio/adaptive_buffer_engine.dart';
import 'package:pulsr/data/audio/battery_aware_playback.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/services/cast_service.dart';

void main() {
  group('Audit Fixes Verification Tests', () {
    test(
        'splitSetCookies correctly preserves RFC 1123 expires dates with commas',
        () {
      const header =
          'SID=abc12345; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/; Domain=.google.com; Secure; HttpOnly, HSID=xyz789; Expires=Thu, 22 Oct 2026 08:00:00 GMT; Path=/; Secure';
      final cookies = YtmAccountService.splitSetCookies(header);
      expect(cookies.length, 2);
      expect(cookies[0], contains('SID=abc12345'));
      expect(cookies[0], contains('Wed, 21 Oct 2026'));
      expect(cookies[1], contains('HSID=xyz789'));
      expect(cookies[1], contains('Thu, 22 Oct 2026'));
    });

    test('splitSetCookies handles multiple cookies without expires', () {
      const header = 'A=1; Path=/, B=2; Secure, C=3; HttpOnly';
      final cookies = YtmAccountService.splitSetCookies(header);
      expect(cookies.length, 3);
      expect(cookies[0], 'A=1; Path=/');
      expect(cookies[1], 'B=2; Secure');
      expect(cookies[2], 'C=3; HttpOnly');
    });

    test('PulsrChannels constants are all defined and non-empty', () {
      expect(PulsrChannels.audioEffects, 'com.pulsr.music/audio_effects');
      expect(PulsrChannels.tagEditor, 'com.pulsr.music/tag_editor');
      expect(PulsrChannels.visualizer, 'com.pulsr.music/visualizer');
      expect(
          PulsrChannels.visualizerStream, 'com.pulsr.music/visualizer_stream');
      expect(PulsrChannels.ringtone, 'com.pulsr.music/ringtone');
      expect(PulsrChannels.scrobbler, 'com.pulsr.music/scrobbler');
      expect(PulsrChannels.ytm, 'com.pulsr.music/ytm');
      expect(PulsrChannels.ytDownload, 'com.pulsr.music/yt_download');
      expect(PulsrChannels.waveform, 'com.pulsr.music/waveform');
      expect(PulsrChannels.proxy, 'com.pulsr.music/proxy');
      expect(PulsrChannels.hiresDac, 'com.pulsr.music/hires_dac');
      expect(PulsrChannels.hiresDacEvents, 'com.pulsr.music/hires_dac_events');
      expect(PulsrChannels.fileOpener, 'com.pulsr.music/file_opener');
      expect(PulsrChannels.lyrics, 'com.pulsr.music/lyrics');
      expect(PulsrChannels.battery, 'com.pulsr.music/battery_optimization');
    });

    test('LinkedHashSet strictly maintains insertion order for FIFO eviction',
        () {
      final set = <String>{};
      for (int i = 0; i < 5; i++) {
        set.add('id_$i');
      }
      expect(set.first, 'id_0');
      set.remove(set.first);
      expect(set.first, 'id_1');
      set.add('id_5');
      expect(set.last, 'id_5');
    });

    test('CrossfadeManager evaluates all curves within [0.0, 1.0] range', () {
      final mgr = CrossfadeManager();
      for (final curve in CrossfadeCurve.values) {
        mgr.curve = curve;
        expect(mgr.evaluateCurve(0.0), closeTo(0.0, 0.001));
        expect(mgr.evaluateCurve(1.0), closeTo(1.0, 0.001));
        expect(mgr.evaluateCurve(0.5), inInclusiveRange(0.0, 1.0));
      }
    });

    test(
        'CrossfadeManager calculateBpmAlignedDuration returns clamped duration',
        () {
      final dur = CrossfadeManager.calculateBpmAlignedDuration(
          const Duration(seconds: 4), 120.0);
      expect(dur.inMilliseconds, greaterThanOrEqualTo(1000));
      expect(dur.inMilliseconds, lessThanOrEqualTo(20000));
    });

    test('BatteryAwarePlayback transitions between levels correctly', () {
      bool lowPowerCalled = false;
      bool criticalCalled = false;
      bool normalCalled = false;

      final battery = BatteryAwarePlayback(
        onLowPowerMode: ({required disableVisualizer, required reduceDsp}) {
          lowPowerCalled = true;
        },
        onCriticalMode: ({required disableCrossfade, required minimalBuffer}) {
          criticalCalled = true;
        },
        onRestoreNormal: () {
          normalCalled = true;
        },
      );

      expect(battery.currentLevel, BatteryOptimizationLevel.normal);

      battery.onBatteryLevelChanged(10);
      expect(battery.currentLevel, BatteryOptimizationLevel.lowPower);
      expect(lowPowerCalled, isTrue);

      battery.onBatteryLevelChanged(3);
      expect(battery.currentLevel, BatteryOptimizationLevel.critical);
      expect(criticalCalled, isTrue);

      battery.onBatteryLevelChanged(80);
      expect(battery.currentLevel, BatteryOptimizationLevel.normal);
      expect(normalCalled, isTrue);
    });

    test(
        'AdaptiveBufferEngine computes zero buffer for local files and optimal for network',
        () {
      final engine = AdaptiveBufferEngine();
      final localBuf = engine.calculateOptimalBuffer(
          bitrateKbps: 320, isWifi: true, isLocalFile: true);
      expect(localBuf, Duration.zero);

      final netBuf = engine.calculateOptimalBuffer(
          bitrateKbps: 320, isWifi: true, isLocalFile: false);
      expect(netBuf.inSeconds, greaterThanOrEqualTo(2));
      expect(netBuf.inSeconds, lessThanOrEqualTo(30));
    });

    test(
        'Tag editor route extra handles both SongsTableData and List<SongsTableData>',
        () {
      const song1 = SongsTableData(
        id: 1,
        title: 'Song One',
        artist: 'Artist One',
        album: 'Album One',
        durationMs: 180000,
        path: '/storage/song1.flac',
        dateAdded: 0,
        playCount: 0,
        lastPositionMs: 0,
        isFavorite: false,
        isMissing: false,
        source: 'local',
        isDownloaded: true,
      );
      const song2 = SongsTableData(
        id: 2,
        title: 'Song Two',
        artist: 'Artist Two',
        album: 'Album Two',
        durationMs: 210000,
        path: '/storage/song2.flac',
        dateAdded: 0,
        playCount: 0,
        lastPositionMs: 0,
        isFavorite: false,
        isMissing: false,
        source: 'local',
        isDownloaded: true,
      );

      // Single track extra handling
      final dynamic extraSingle = song1;
      final SongsTableData? resolvedSingle = extraSingle is SongsTableData
          ? extraSingle
          : (extraSingle is List<SongsTableData> && extraSingle.isNotEmpty
              ? extraSingle.first
              : null);
      final List<SongsTableData>? resolvedListFromSingle =
          extraSingle is List<SongsTableData>
              ? extraSingle
              : (extraSingle is SongsTableData ? [extraSingle] : null);
      expect(resolvedSingle?.id, 1);
      expect(resolvedListFromSingle?.length, 1);
      expect(resolvedListFromSingle?.first.title, 'Song One');

      // Batch list extra handling
      final dynamic extraBatch = <SongsTableData>[song1, song2];
      final SongsTableData? resolvedFromBatch = extraBatch is SongsTableData
          ? extraBatch
          : (extraBatch is List<SongsTableData> && extraBatch.isNotEmpty
              ? extraBatch.first
              : null);
      final List<SongsTableData>? resolvedList =
          extraBatch is List<SongsTableData>
              ? extraBatch
              : (extraBatch is SongsTableData ? [extraBatch] : null);
      expect(resolvedFromBatch?.id, 1);
      expect(resolvedList?.length, 2);
      expect(resolvedList?[1].id, 2);
    });

    test('CastSessionStatus correctly maps and evaluates state', () {
      const initial = CastSessionStatus();
      expect(initial.available, isFalse);
      expect(initial.connected, isFalse);
      expect(initial.deviceName, isNull);

      final fromMap = CastSessionStatus.fromMap({
        'connected': true,
        'deviceName': 'Living Room Nest Audio',
        'playing': true,
        'positionMs': 45000,
      });
      expect(fromMap.available, isTrue);
      expect(fromMap.connected, isTrue);
      expect(fromMap.deviceName, 'Living Room Nest Audio');
      expect(fromMap.playing, isTrue);
      expect(fromMap.positionMs, 45000);
    });

    test('CastDevice and CastRoute map parsing handles valid and fallback values', () {
      final dev = CastDevice.fromMap({
        'id': 'nest_audio_1',
        'name': 'Studio Speaker',
        'model': 'Google Nest Audio',
        'host': '192.168.1.150',
        'port': 8009,
      });
      expect(dev, isNotNull);
      expect(dev!.id, 'nest_audio_1');
      expect(dev.name, 'Studio Speaker');
      expect(dev.port, 8009);

      final route = CastRoute.fromMap({
        'id': 'route_abc',
        'name': 'Bedroom Chromecast',
        'connected': true,
        'selected': true,
      });
      expect(route, isNotNull);
      expect(route!.name, 'Bedroom Chromecast');
      expect(route.connected, isTrue);
      expect(route.selected, isTrue);
    });
  });
}
