// test/features/ytm_browse/ytm_browse_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_browse_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/ytm_browse/presentation/ytm_browse_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtmBrowseService extends Mock implements YtmBrowseService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockYtmBrowseService mockBrowse;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockBrowse = MockYtmBrowseService();
    getIt.registerSingleton<YtmBrowseService>(mockBrowse);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Widget host() => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const YtmBrowseScreen(),
      );

  testWidgets('renders loading skeleton while the feed is in flight',
      (tester) async {
    when(() => mockBrowse.getHomeFeed())
        .thenAnswer((_) => Future<List<YtmBrowseSection>>.delayed(
              const Duration(seconds: 5),
              () => const [],
            ));

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(YtmBrowseScreen), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Let the pending future resolve so no timer leaks into teardown.
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('renders the empty state when the feed has no items',
      (tester) async {
    when(() => mockBrowse.getHomeFeed()).thenAnswer((_) async => const []);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byType(YtmBrowseScreen), findsOneWidget);
    expect(find.byIcon(Icons.explore_off_rounded), findsOneWidget);
    expect(find.text('No recommendations right now.'), findsOneWidget);
  });

  testWidgets('drops empty sections and renders only populated ones',
      (tester) async {
    when(() => mockBrowse.getHomeFeed()).thenAnswer((_) async => const [
          YtmBrowseSection(title: 'Empty Section', items: []),
          YtmBrowseSection(title: 'Top Charts & Trending', items: [
            YtmBrowseItem(
              id: 'dQw4w9WgXcQ',
              title: 'Never Gonna Give You Up',
              subtitle: 'Rick Astley',
              type: 'song',
            ),
          ]),
        ]);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Top Charts & Trending'), findsOneWidget);
    expect(find.text('Never Gonna Give You Up'), findsOneWidget);
    expect(find.text('Empty Section'), findsNothing);
  });

  testWidgets('renders the error state with a retry action when the feed throws',
      (tester) async {
    when(() => mockBrowse.getHomeFeed())
        .thenAnswer((_) async => throw Exception('network down'));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(find.text('Retry'), findsWidgets);
  });

  testWidgets('the refresh action re-invokes the feed', (tester) async {
    var calls = 0;
    when(() => mockBrowse.getHomeFeed()).thenAnswer((_) async {
      calls++;
      return const [];
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.byIcon(Icons.refresh_rounded).first);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
