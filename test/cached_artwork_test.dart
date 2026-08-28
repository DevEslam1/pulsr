// test/cached_artwork_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/artwork_placeholder.dart';
import 'package:pulsr/core/widgets/cached_artwork.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AuraTheme.customTheme(const Color(0xFF9B9EF5),
        brightness: Brightness.dark),
    home: Scaffold(body: child),
  );
}

void main() {
  group('CachedArtwork Widget Tests', () {
    testWidgets('Renders placeholder when no cached bytes available',
        (tester) async {
      final customCache = ArtworkLruCache.withCapacity(10);
      customCache.put('AUDIO_1', null); // Cached as missing

      await tester.pumpWidget(
        _wrap(
          CachedArtwork(
            id: 1,
            type: ArtworkType.AUDIO,
            customCache: customCache,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ArtworkPlaceholder), findsOneWidget);
    });

    testWidgets('Renders Image.memory when cached bytes present',
        (tester) async {
      final customCache = ArtworkLruCache.withCapacity(10);

      // Create 1x1 transparent PNG bytes
      final samplePng = Uint8List.fromList([
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        13,
        73,
        72,
        68,
        82,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        8,
        6,
        0,
        0,
        0,
        31,
        213,
        196,
        200,
        0,
        0,
        0,
        13,
        73,
        68,
        65,
        84,
        120,
        156,
        99,
        96,
        248,
        15,
        0,
        1,
        5,
        1,
        2,
        162,
        162,
        190,
        253,
        0,
        0,
        0,
        0,
        73,
        69,
        78,
        68,
        174,
        66,
        96,
        130
      ]);

      customCache.put('AUDIO_100', samplePng);

      await tester.pumpWidget(
        _wrap(
          CachedArtwork(
            id: 100,
            type: ArtworkType.AUDIO,
            size: 64.0,
            customCache: customCache,
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
    });
  });
}
