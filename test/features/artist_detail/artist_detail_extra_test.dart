// ArtistDetailScreen branches the primary suite misses: the populated bio
// card, the bio error fallback, and the artist-id change that re-resolves
// streams and biography via didUpdateWidget.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/artist_bio_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/features/artist_detail/presentation/artist_detail_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _Artists extends Mock implements GetArtistsUseCase {}

class _RecordingBioService extends ArtistBioService {
  _RecordingBioService({this.result, this.error});
  final ArtistInfo? result;
  final Object? error;
  int calls = 0;

  @override
  Future<ArtistInfo?> getArtistInfo(String artistName) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }

  @override
  void dispose() {}
}

const _artistA = ArtistsTableData(
  id: 1,
  name: 'Artist One',
  songCount: 3,
  albumCount: 1,
);
const _artistB = ArtistsTableData(
  id: 2,
  name: 'Artist Two',
  songCount: 5,
  albumCount: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Artists useCase;

  setUpAll(() {
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    useCase = _Artists();
    when(() => useCase.watchArtistAlbums(any()))
        .thenAnswer((_) => Stream.value(const Right(<AlbumsTableData>[])));
    when(() => useCase.watchArtistSongs(any()))
        .thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));
  });

  tearDown(() async {
    await getIt.reset();
  });

  void registerBio(ArtistBioService bio) {
    if (getIt.isRegistered<ArtistBioService>()) {
      getIt.unregister<ArtistBioService>();
    }
    getIt.registerSingleton<ArtistBioService>(bio);
  }

  Widget wrap(ArtistDetailScreen screen) => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<PlayerCubit>.value(
          value: stubPlayerCubit(),
          child: screen,
        ),
      );

  testWidgets('renders the biography card when a bio is available',
      (tester) async {
    registerBio(_RecordingBioService(
      result: const ArtistInfo(
        name: 'Artist One',
        bio: 'A prolific session musician.',
      ),
    ));

    await tester.pumpWidget(wrap(
      ArtistDetailScreen(artist: _artistA, getArtistsUseCase: useCase),
    ));
    await tester.pumpAndSettle();

    expect(find.text('About Artist'), findsOneWidget);
    expect(find.text('A prolific session musician.'), findsOneWidget);
  });

  testWidgets('renders the bio fallback on service failure', (tester) async {
    registerBio(_RecordingBioService(error: Exception('network')));

    await tester.pumpWidget(wrap(
      ArtistDetailScreen(artist: _artistA, getArtistsUseCase: useCase),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bio unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the artist re-resolves streams and biography',
      (tester) async {
    final bio = _RecordingBioService(
      result: const ArtistInfo(name: 'x', bio: 'bio'),
    );
    registerBio(bio);

    await tester.pumpWidget(wrap(
      ArtistDetailScreen(artist: _artistA, getArtistsUseCase: useCase),
    ));
    await tester.pumpAndSettle();
    expect(bio.calls, 1);

    await tester.pumpWidget(wrap(
      ArtistDetailScreen(artist: _artistB, getArtistsUseCase: useCase),
    ));
    await tester.pumpAndSettle();

    expect(bio.calls, 2);
    expect(find.text('Artist Two'), findsWidgets);
  });
}
