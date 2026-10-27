import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/cached_artwork.dart';
import 'package:pulsr/core/widgets/pulsr_artwork_header.dart';

void main() {
  testWidgets('falls back to a clean surface without artwork', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      home: const Scaffold(
        body: PulsrArtworkHeader(
          title: 'Library',
          subtitle: '9 songs · 4 albums',
          albumIds: [],
        ),
      ),
    ));
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('9 songs · 4 albums'), findsOneWidget);
    expect(find.byType(CachedArtwork), findsNothing);
  });

  testWidgets('renders at most four album covers', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      home: const Scaffold(
        body: PulsrArtworkHeader(
          title: 'Search',
          albumIds: [1, 2, 3, 4, 5],
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Search'), findsOneWidget);
    expect(find.byType(CachedArtwork), findsNWidgets(4));
  });
}
