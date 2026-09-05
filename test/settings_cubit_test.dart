import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/network/proxy_config.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockMediaScannerService mockScannerService;

  setUp(() {
    mockScannerService = MockMediaScannerService();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('SettingsCubit', () {
    test('initial state defaults are correct', () {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      expect(cubit.state.gaplessPlayback, true);
      expect(cubit.state.crossfadeSeconds, 0.0);
      expect(cubit.state.minDurationSec, 30);
      expect(cubit.state.dynamicThemingEnabled, true);
      expect(cubit.state.resumeAfterInterruption, true);
      expect(cubit.state.isScanning, false);

      cubit.close();
    });

    test('setResumeAfterInterruption updates state and SharedPreferences',
        () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      await cubit.setResumeAfterInterruption(false);
      expect(cubit.state.resumeAfterInterruption, false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_resume_after_interruption'), false);

      cubit.close();
    });

    test(
        'setGapless, setCrossfade, setMinDuration, setDynamicTheming update state',
        () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      await cubit.setGapless(false);
      expect(cubit.state.gaplessPlayback, false);

      await cubit.setMinDuration(15);
      expect(cubit.state.minDurationSec, 15);

      await cubit.setDynamicTheming(false);
      expect(cubit.state.dynamicThemingEnabled, false);

      cubit.close();
    });

    test('setAutoHideSystemMedia updates state and SharedPreferences',
        () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      await cubit.setAutoHideSystemMedia(false);
      expect(cubit.state.autoHideSystemMedia, false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_auto_hide_system_media'), false);

      await cubit.setAutoHideSystemMedia(true);
      expect(cubit.state.autoHideSystemMedia, true);

      cubit.close();
    });

    test(
        'setWifiOnlyMode and setOfflineOnlyMode update state and SharedPreferences',
        () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      expect(cubit.state.wifiOnlyMode, false);
      expect(cubit.state.offlineOnlyMode, false);

      await cubit.setWifiOnlyMode(true);
      expect(cubit.state.wifiOnlyMode, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_wifi_only_mode'), true);

      await cubit.setOfflineOnlyMode(true);
      expect(cubit.state.offlineOnlyMode, true);
      expect(prefs.getBool('setting_offline_only_mode'), true);

      cubit.close();
    });

    test('proxy settings update state and SharedPreferences', () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.proxyEnabled, false);

      await cubit.setProxySettings(
        enabled: true,
        type: AppProxyType.socks5,
        host: '127.0.0.1',
        port: 9050,
        username: 'admin',
        password: '123',
        bypassHosts: 'localhost',
      );

      expect(cubit.state.proxyEnabled, true);
      expect(cubit.state.proxyType, AppProxyType.socks5);
      expect(cubit.state.proxyHost, '127.0.0.1');
      expect(cubit.state.proxyPort, 9050);
      expect(cubit.state.hasProxyPassword, true);
      expect(await cubit.getProxyPassword(), '123');
      expect(cubit.state.proxyBypassHosts, 'localhost');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_proxy_enabled'), true);
      expect(prefs.getString('setting_proxy_type'), 'socks5');
      expect(prefs.getString('setting_proxy_host'), '127.0.0.1');
      expect(prefs.getInt('setting_proxy_port'), 9050);

      await cubit.setProxyEnabled(false);
      expect(cubit.state.proxyEnabled, false);
      expect(prefs.getBool('setting_proxy_enabled'), false);

      cubit.close();
    });

    test(
        'MediaScannerService.isSystemIgnoredPath accurately detects recordings & messenger media',
        () {
      // WhatsApp Voice Notes & Audio
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/WhatsApp/Media/WhatsApp Voice Notes/2023/PTT-123.opus'),
          true);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio/AUD-20230501-WA0001.mp3'),
          true);

      // Telegram Audio / Voice
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Telegram/Telegram Audio/voice_message.ogg'),
          true);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Android/media/org.telegram.messenger/Telegram/Telegram Voice/audio.ogg'),
          true);

      // Voice & Call Recorders
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Recordings/Call/Call_20230401.m4a'),
          true);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/MIUI/sound_recorder/rec_01.mp3'),
          true);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/VoiceRecorder/note.m4a'),
          true);

      // System Tones & Hidden folders
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Notifications/ping.mp3'),
          true);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Ringtones/marimba.mp3'),
          true);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/.thumbnails/cache.mp3'),
          true);

      // Legitimate Music Files should NOT be ignored
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Music/Daft Punk - Discovery/01 - One More Time.flac'),
          false);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Download/Pink Floyd - Time.mp3'),
          false);
    });

    test(
        'importProxiesFromText, selectProxyEntry, removeProxyEntry and sortProxiesByLatency work correctly',
        () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      const rawText = '''
31.59.20.176:6754:qmyizdto:n5fui7pyec1q
45.38.107.97:6014:qmyizdto:n5fui7pyec1q
198.105.121.200:6462:qmyizdto:n5fui7pyec1q
''';

      final count =
          await cubit.importProxiesFromText(rawText, autoSelectFirst: true);
      expect(count, 3);
      expect(cubit.state.proxyList.length, 3);
      expect(cubit.state.proxyEnabled, true);
      expect(cubit.state.proxyHost, '31.59.20.176');
      expect(cubit.state.proxyPort, 6754);
      expect(cubit.state.proxyUsername, 'qmyizdto');

      // Select another proxy
      final second = cubit.state.proxyList[1];
      await cubit.selectProxyEntry(second);
      expect(cubit.state.proxyHost, '45.38.107.97');
      expect(cubit.state.proxyPort, 6014);

      // Remove third proxy
      final thirdId = cubit.state.proxyList[2].id;
      await cubit.removeProxyEntry(thirdId);
      expect(cubit.state.proxyList.length, 2);

      // Add with latency and sort
      await cubit.addProxyEntry(
        const ProxyEntry(
          id: 'fast_proxy',
          host: '1.1.1.1',
          port: 8080,
          isWorking: true,
          latencyMs: 50,
        ),
      );

      await cubit.sortProxiesByLatency();
      expect(cubit.state.proxyList.first.host, '1.1.1.1');

      cubit.close();
    });

    test(
        'proxy list and active proxy settings persist across simulated app relaunch',
        () async {
      // 1. First app session: import proxies and select one
      final cubitSession1 = SettingsCubit(scannerService: mockScannerService);
      const rawText = '''
31.59.20.176:6754:qmyizdto:n5fui7pyec1q
45.38.107.97:6014:qmyizdto:n5fui7pyec1q
''';
      await cubitSession1.importProxiesFromText(rawText);
      await cubitSession1.selectProxyEntry(cubitSession1.state.proxyList[1]);
      await cubitSession1.close();

      // 2. Second app session (relaunch): creates a new cubit instance reading from SharedPreferences
      final cubitSession2 = SettingsCubit(scannerService: mockScannerService);
      // Wait for initial asynchronous _loadPreferences to complete and emit
      await expectLater(
        cubitSession2.stream,
        emits(predicate<SettingsState>((s) => s.proxyList.length == 2)),
      );

      expect(cubitSession2.state.proxyList.length, 2);
      expect(cubitSession2.state.proxyList[0].host, '31.59.20.176');
      expect(cubitSession2.state.proxyList[1].host, '45.38.107.97');
      expect(cubitSession2.state.proxyEnabled, true);
      expect(cubitSession2.state.proxyHost, '45.38.107.97');
      expect(cubitSession2.state.proxyPort, 6014);
      expect(cubitSession2.state.proxyUsername, 'qmyizdto');

      await cubitSession2.close();
    });

    test('audibleLatencyOffset only applies to Bluetooth output', () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);
      await cubit.setBluetoothLatencyOffsetMs(200);

      const wired = AudioOutputInfo(
        deviceName: 'Wired Headset',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
      );
      const bluetooth = AudioOutputInfo(
        deviceName: 'WH-1000XM5',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
        isBluetooth: true,
      );

      expect(cubit.state.audibleLatencyOffset, Duration.zero);
      expect(
        cubit.state.copyWith(currentOutputDevice: wired).audibleLatencyOffset,
        Duration.zero,
      );
      expect(
        cubit.state
            .copyWith(currentOutputDevice: bluetooth)
            .audibleLatencyOffset,
        const Duration(milliseconds: 200),
      );

      await cubit.close();
    });

    test('pool credentials stay out of SharedPreferences and survive relaunch',
        () async {
      final session1 = SettingsCubit(scannerService: mockScannerService);
      await session1
          .importProxiesFromText('31.59.20.176:6754:qmyizdto:n5fui7pyec1q');
      await session1.close();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('setting_proxy_list'),
          isNot(contains('n5fui7pyec1q')));

      final session2 = SettingsCubit(scannerService: mockScannerService);
      await expectLater(
        session2.stream,
        emits(predicate<SettingsState>((s) => s.proxyList.length == 1)),
      );
      expect(session2.state.proxyList.first.password, 'n5fui7pyec1q');

      await session2.close();
    });

    test('legacy plaintext pool passwords migrate into secure storage',
        () async {
      SharedPreferences.setMockInitialValues({
        'setting_proxy_list': jsonEncode([
          {
            'id': 'legacy_1',
            'host': '198.105.121.200',
            'port': 6462,
            'username': 'qmyizdto',
            'password': 'n5fui7pyec1q',
            'type': 'http',
          }
        ]),
      });

      final cubit = SettingsCubit(scannerService: mockScannerService);
      await expectLater(
        cubit.stream,
        emits(predicate<SettingsState>((s) => s.proxyList.length == 1)),
      );

      expect(cubit.state.proxyList.first.password, 'n5fui7pyec1q');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('setting_proxy_list'),
          isNot(contains('n5fui7pyec1q')));

      await cubit.close();
    });
  });
}
