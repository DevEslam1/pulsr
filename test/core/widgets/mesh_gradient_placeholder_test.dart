// test/core/widgets/mesh_gradient_placeholder_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/artwork_placeholder.dart';
import 'package:pulsr/core/widgets/mesh_gradient_placeholder.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AuraTheme.customTheme(const Color(0xFF9B9EF5),
        brightness: Brightness.dark),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('MeshGradientPlaceholder', () {
    test('computeSeed produces stable, deterministic seeds', () {
      final s1 = MeshGradientPlaceholder.computeSeed(
        seed: 10,
        title: 'Bahareya',
        artist: 'Mohamed Hamaki',
      );
      final s2 = MeshGradientPlaceholder.computeSeed(
        seed: 10,
        title: 'Bahareya',
        artist: 'Mohamed Hamaki',
      );
      final s3 = MeshGradientPlaceholder.computeSeed(
        seed: 11,
        title: 'Bahareya',
        artist: 'Mohamed Hamaki',
      );

      expect(s1, equals(s2));
      expect(s1, isNot(equals(s3)));
    });

    test('extractInitials extracts initials accurately', () {
      expect(
        MeshGradientPlaceholder.extractInitials(
          title: 'Bahareya',
          artist: 'Mohamed Hamaki',
        ),
        'BA',
      );

      expect(
        MeshGradientPlaceholder.extractInitials(
          title: 'Bohemian Rhapsody',
          artist: 'Queen',
        ),
        'BR',
      );

      expect(
        MeshGradientPlaceholder.extractInitials(
          title: '',
          artist: 'Mohamed Hamaki',
        ),
        'MH',
      );

      expect(
        MeshGradientPlaceholder.extractInitials(
          title: 'A',
          artist: '',
        ),
        'A',
      );
    });

    testWidgets('renders MeshGradientPlaceholder with custom initials',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const MeshGradientPlaceholder(
          size: 64,
          title: 'Bahareya',
          artist: 'Mohamed Hamaki',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(MeshGradientPlaceholder), findsOneWidget);
      expect(find.text('BA'), findsOneWidget);
    });

    testWidgets('renders icon when explicit icon is provided', (tester) async {
      await tester.pumpWidget(_wrap(
        const MeshGradientPlaceholder(
          size: 64,
          icon: Icons.album_rounded,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.album_rounded), findsOneWidget);
    });

    testWidgets('ArtworkPlaceholder delegates to MeshGradientPlaceholder',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ArtworkPlaceholder(
          size: 56,
          title: 'Comfortably Numb',
          artist: 'Pink Floyd',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ArtworkPlaceholder), findsOneWidget);
      expect(find.byType(MeshGradientPlaceholder), findsOneWidget);
      expect(find.text('CN'), findsOneWidget);
    });

    testWidgets(
        'renders card-size frosted editorial medallion for Arabic and Latin titles',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MeshGradientPlaceholder(
              size: 138,
              borderRadius: 18,
              title: 'محمد رمضان',
              artist: 'حبيبي انا',
            ),
            MeshGradientPlaceholder(
              size: 138,
              borderRadius: 18,
              title: 'pulsr-playback-smoke',
              artist: 'Unknown',
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(MeshGradientPlaceholder), findsNWidgets(2));
      expect(find.text('مر'), findsOneWidget);
      expect(find.text('PU'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNWidgets(2));
    });

    testWidgets('skips BackdropFilter under high contrast accessibility mode',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: const MediaQuery(
            data: MediaQueryData(highContrast: true),
            child: Scaffold(
              body: Center(
                child: MeshGradientPlaceholder(
                  size: 138,
                  borderRadius: 18,
                  title: 'Pulsr Smoke',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PS'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });
}
