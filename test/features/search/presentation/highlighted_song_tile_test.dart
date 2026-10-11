// test/features/search/presentation/highlighted_song_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/highlighted_text.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/search/presentation/widgets/highlighted_song_tile.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTile(
    WidgetTester tester, {
    required String query,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    VoidCallback? onMorePressed,
    Widget? trailing,
  }) async {
    final player = stubPlayerCubit();
    final song =
        createTestSong(id: 1, title: 'Beat Flow', artist: 'Beat Maker');
    await tester.pumpWidget(screenHarness(
      providers: [BlocProvider<PlayerCubit>.value(value: player)],
      child: Scaffold(
        body: HighlightedSongTile(
          song: song,
          query: query,
          onTap: onTap ?? () {},
          onLongPress: onLongPress,
          onMorePressed: onMorePressed,
          trailing: trailing,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('highlights the query in both title and subtitle',
      (tester) async {
    await pumpTile(tester, query: 'Beat');

    final texts = tester
        .widgetList<PulsrHighlightedText>(find.byType(PulsrHighlightedText))
        .toList();
    expect(texts.length, 2);
    expect(texts.every((w) => w.query == 'Beat'), isTrue);
    expect(texts.map((w) => w.text), containsAll(['Beat Flow', 'Beat Maker']));

    // Ellipsis behavior is preserved.
    expect(texts.every((w) => w.maxLines == 1), isTrue);
    expect(texts.every((w) => w.overflow == TextOverflow.ellipsis), isTrue);
  });

  testWidgets('renders plain text when the query is empty', (tester) async {
    await pumpTile(tester, query: '');
    expect(find.text('Beat Flow'), findsOneWidget);
  });

  testWidgets('reports tap, long-press and more callbacks', (tester) async {
    var taps = 0;
    var longPresses = 0;
    var more = 0;
    await pumpTile(
      tester,
      query: 'Beat',
      onTap: () => taps++,
      onLongPress: () => longPresses++,
      onMorePressed: () => more++,
    );

    await tester.tap(find.text('Beat Flow'));
    await tester.pump();
    expect(taps, 1);

    await tester.longPress(find.byType(HighlightedSongTile));
    await tester.pump();
    expect(longPresses, 1);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pump();
    expect(more, 1);
  });
}
