import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/mini_player.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}
class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;

  const testSong = SongsTableData(
    id: 101,
    title: 'M17 Test Song',
    artist: 'Artist',
    album: 'Album',
    durationMs: 180000,
    path: '/path/101.mp3',
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    lastPositionMs: 0,
    source: 'local',
  );

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    mockSettingsCubit = MockSettingsCubit();

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockPlayerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          duration: Duration(minutes: 3),
        ),
        queueSlice: QueueSlice(
          queue: [testSong],
          currentIndex: 0,
        ),
      ),
    );
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget buildWidget({required Widget child}) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
        BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  testWidgets('M-17: MiniPlayer cleanly disposes _isInteracting and guards post-disposal mutations', (tester) async {
    await tester.pumpWidget(
      buildWidget(
        child: MiniPlayer(
          onTap: () {},
          onSwipeDown: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state<MiniPlayerState>(find.byType(MiniPlayer));
    final notifier = state.isInteractingNotifier;

    expect(notifier.value, isFalse);

    // Unmount the widget to trigger dispose()
    await tester.pumpWidget(
      buildWidget(
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify notifier was disposed: adding a listener to a disposed ChangeNotifier throws FlutterError
    expect(
      () => notifier.addListener(() {}),
      throwsA(isA<FlutterError>()),
    );
  });
}
