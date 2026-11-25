// test/features/player/radio_recommendations_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ambient_sound_service.dart';
import 'package:pulsr/core/services/quran_mode_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/quran_mode_profile.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/radio_now_playing_recommendations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_audio_player.dart';
import 'widgets/player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AmbientSoundService.playerFactory = () => FakeAudioPlayer();
  });

  tearDown(() {
    AmbientSoundService.playerFactory = () => FakeAudioPlayer();
  });

  const radioSong = SongsTableData(
    id: 99,
    title: 'Holy Quran Cairo',
    artist: 'Radio',
    album: '',
    durationMs: 0,
    path: 'https://stream.radiojar.com/8s5u8xamm',
    source: SongSource.radio,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    lastPositionMs: 0,
  );

  const localSong = SongsTableData(
    id: 101,
    title: 'Local Track',
    artist: 'Artist',
    album: 'Album',
    durationMs: 180000,
    path: '/music/track.mp3',
    source: SongSource.local,
    isFavorite: false,
    isMissing: false,
    isDownloaded: true,
    playCount: 0,
    lastPositionMs: 0,
  );

  const onlineSong = SongsTableData(
    id: 102,
    title: 'YouTube Track',
    artist: 'Artist',
    album: '',
    durationMs: 200000,
    path: 'ytmusic://dQw4w9WgXcQ',
    source: SongSource.youtube,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    lastPositionMs: 0,
  );

  group('Radio Recommendations & Always on Radio', () {
    testWidgets('shows recommendations when radio is playing', (tester) async {
      final state = const PlayerState(
        playback: PlaybackSlice(isPlaying: true, currentSong: radioSong),
      );
      final cubit = stubPlayerCubit(state: state);

      final props = PlayerThemeProps(
        state: state,
        cubit: cubit,
        activeColor: Colors.teal,
        bgColor: Colors.black,
      );

      await tester.pumpWidget(
        sheetHost(
          playerCubit: cubit,
          child: RadioNowPlayingRecommendations(
            props: props,
            cubit: cubit,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RadioNowPlayingRecommendations), findsOneWidget);
      expect(find.text('Quran Mode'), findsWidgets);
      expect(find.text('Ambient Sounds'), findsWidgets);
    });

    testWidgets(
        'header fits a phone-width banner without overflowing the tab row',
        (tester) async {
      final state = const PlayerState(
        playback: PlaybackSlice(isPlaying: true, currentSong: radioSong),
      );
      final cubit = stubPlayerCubit(state: state);

      final props = PlayerThemeProps(
        state: state,
        cubit: cubit,
        activeColor: Colors.teal,
        bgColor: Colors.black,
      );

      await tester.pumpWidget(
        sheetHost(
          playerCubit: cubit,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 420,
              child: RadioNowPlayingRecommendations(
                props: props,
                cubit: cubit,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Quran Mode'), findsWidgets);
      expect(find.text('Ambient Sounds'), findsWidgets);
    });

    testWidgets('hides recommendations when local or online track is playing',
        (tester) async {
      final state = const PlayerState(
        playback: PlaybackSlice(isPlaying: true, currentSong: localSong),
      );
      final cubit = stubPlayerCubit(state: state);

      final props = PlayerThemeProps(
        state: state,
        cubit: cubit,
        activeColor: Colors.teal,
        bgColor: Colors.black,
      );

      await tester.pumpWidget(
        sheetHost(
          playerCubit: cubit,
          child: RadioNowPlayingRecommendations(
            props: props,
            cubit: cubit,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Radio Recommendations'), findsNothing);
    });

    test(
        'Quran mode defaults to Tajweed (Mujawwad) and saves user choice as default',
        () async {
      final service = QuranModeService();
      // Default when no preference exists:
      final initialStyle = await service.getStyle();
      expect(initialStyle, QuranReciterStyle.mujawwad);

      // When user changes style, it persists and becomes the new default
      await service.setStyle(QuranReciterStyle.tarawih);
      final changedStyle = await service.getStyle();
      expect(changedStyle, QuranReciterStyle.tarawih);
    });

    test('Quran mode Always on Radio persists correctly', () async {
      final service = QuranModeService();
      expect(await service.isAlwaysOnRadio(), isFalse);

      await service.setAlwaysOnRadio(true);
      expect(await service.isAlwaysOnRadio(), isTrue);

      await service.setAlwaysOnRadio(false);
      expect(await service.isAlwaysOnRadio(), isFalse);
    });

    test(
        'Ambient Sound Always on Radio auto-enables for radio and disables for local/online',
        () async {
      final ambient = AmbientSoundService();
      await ambient.init();
      expect(ambient.alwaysOnRadio, isFalse);

      await ambient.setAlwaysOnRadio(true);
      expect(ambient.alwaysOnRadio, isTrue);

      // Simulate radio track starting
      ambient.onCurrentSongChanged(radioSong);
      expect(ambient.isEnabled, isTrue);

      // Simulate local track starting -> should disable
      ambient.onCurrentSongChanged(localSong);
      expect(ambient.isEnabled, isFalse);

      // Simulate radio starting again -> should auto-enable
      ambient.onCurrentSongChanged(radioSong);
      expect(ambient.isEnabled, isTrue);

      // Simulate online track starting -> should disable
      ambient.onCurrentSongChanged(onlineSong);
      expect(ambient.isEnabled, isFalse);

      // Clean up
      await ambient.setAlwaysOnRadio(false);
      await ambient.setEnabled(false);
    });

    test(
        'Ambient Sound saves user choices and volume percentages across disable/enable',
        () async {
      final ambient = AmbientSoundService();
      await ambient.init();

      // Set custom volume percentage
      await ambient.setEffectVolume(AmbientSoundEffect.fire, 0.75);
      await ambient.toggleEffect(AmbientSoundEffect.fire);
      expect(ambient.isEffectActive(AmbientSoundEffect.fire), isTrue);
      expect(ambient.volumeFor(AmbientSoundEffect.fire), 0.75);

      // Disabling ambient sounds should not erase saved choices or percentage values
      await ambient.setEnabled(false);
      expect(ambient.isEnabled, isFalse);
      expect(
          ambient.savedUserEffects.contains(AmbientSoundEffect.fire), isTrue);
      expect(ambient.volumeFor(AmbientSoundEffect.fire), 0.75);

      // Re-enabling restores the saved effect and volume percentage
      await ambient.setEnabled(true);
      expect(ambient.isEffectActive(AmbientSoundEffect.fire), isTrue);
      expect(ambient.volumeFor(AmbientSoundEffect.fire), 0.75);

      // Clean up
      await ambient.setEnabled(false);
    });
  });
}
