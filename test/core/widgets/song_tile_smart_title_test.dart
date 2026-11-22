// test/core/widgets/song_tile_smart_title_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSongTile(
    WidgetTester tester, {
    required String title,
    required String artist,
  }) async {
    final player = stubPlayerCubit();
    final song = createTestSong(id: 1, title: title, artist: artist);

    await tester.pumpWidget(screenHarness(
      providers: [BlocProvider<PlayerCubit>.value(value: player)],
      child: Scaffold(
        body: SongTile(
          song: song,
          onTap: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('SongTile Smart Artist - Title Fallback', () {
    testWidgets(
        'displays parsed title and artist when artist is "Unknown Artist" and title contains " - "',
        (tester) async {
      await pumpSongTile(
        tester,
        title: 'Mohamed Hamaki - Bahareya',
        artist: 'Unknown Artist',
      );

      expect(find.text('Bahareya'), findsOneWidget);
      expect(find.text('Mohamed Hamaki'), findsOneWidget);
      expect(find.text('Mohamed Hamaki - Bahareya'), findsNothing);
      expect(find.text('Unknown Artist'), findsNothing);
    });

    testWidgets(
        'displays parsed title and artist when artist is empty and title contains " - "',
        (tester) async {
      await pumpSongTile(
        tester,
        title: 'Mohamed Hamaki - Bahareya',
        artist: '',
      );

      expect(find.text('Bahareya'), findsOneWidget);
      expect(find.text('Mohamed Hamaki'), findsOneWidget);
      expect(find.text('Mohamed Hamaki - Bahareya'), findsNothing);
    });

    testWidgets('preserves original title and artist when artist is already known',
        (tester) async {
      await pumpSongTile(
        tester,
        title: 'Mohamed Hamaki - Bahareya',
        artist: 'Amr Diab',
      );

      expect(find.text('Mohamed Hamaki - Bahareya'), findsOneWidget);
      expect(find.text('Amr Diab'), findsOneWidget);
    });
  });
}
