// test/settings_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockMediaScannerService mockScannerService;

  setUp(() {
    mockScannerService = MockMediaScannerService();
    SharedPreferences.setMockInitialValues({});
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

    test('setResumeAfterInterruption updates state and SharedPreferences', () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      await cubit.setResumeAfterInterruption(false);
      expect(cubit.state.resumeAfterInterruption, false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_resume_after_interruption'), false);

      cubit.close();
    });

    test('setGapless, setCrossfade, setMinDuration, setDynamicTheming update state', () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      await cubit.setGapless(false);
      expect(cubit.state.gaplessPlayback, false);

      await cubit.setMinDuration(15);
      expect(cubit.state.minDurationSec, 15);

      await cubit.setDynamicTheming(false);
      expect(cubit.state.dynamicThemingEnabled, false);

      cubit.close();
    });

    test('setAutoHideSystemMedia updates state and SharedPreferences', () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      await cubit.setAutoHideSystemMedia(false);
      expect(cubit.state.autoHideSystemMedia, false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_auto_hide_system_media'), false);

      await cubit.setAutoHideSystemMedia(true);
      expect(cubit.state.autoHideSystemMedia, true);

      cubit.close();
    });

    test('MediaScannerService.isSystemIgnoredPath accurately detects recordings & messenger media', () {
      // WhatsApp Voice Notes & Audio
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/WhatsApp/Media/WhatsApp Voice Notes/2023/PTT-123.opus'), true);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio/AUD-20230501-WA0001.mp3'), true);

      // Telegram Audio / Voice
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Telegram/Telegram Audio/voice_message.ogg'), true);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Android/media/org.telegram.messenger/Telegram/Telegram Voice/audio.ogg'), true);

      // Voice & Call Recorders
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Recordings/Call/Call_20230401.m4a'), true);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/MIUI/sound_recorder/rec_01.mp3'), true);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/VoiceRecorder/note.m4a'), true);

      // System Tones & Hidden folders
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Notifications/ping.mp3'), true);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Ringtones/marimba.mp3'), true);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/.thumbnails/cache.mp3'), true);

      // Legitimate Music Files should NOT be ignored
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Music/Daft Punk - Discovery/01 - One More Time.flac'), false);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Download/Pink Floyd - Time.mp3'), false);
    });
  });
}
