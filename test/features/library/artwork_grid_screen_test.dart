// Covers lib/features/library/presentation/artwork_grid_screen.dart
//
// Exercises the empty/populated wall, album navigation, the zoom controls and
// the incremental pagination load on scroll.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/artwork_grid_screen.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockLibraryCubit extends Mock implements LibraryCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

AlbumsTableData _album(int id, String title) => AlbumsTableData(
      id: id,
      title: title,
      artist: 'Artist $id',
      songCount: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockLibraryCubit library;
  late MockSettingsCubit settings;

  setUp(() {
    library = MockLibraryCubit();
    settings = MockSettingsCubit();
    when(() => library.stream)
        .thenAnswer((_) => const Stream<LibraryState>.empty());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => settings.rescanLibrary()).thenAnswer((_) async => 0);
  });

  Future<void> pumpGrid(WidgetTester tester, List<AlbumsTableData> albums) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    when(() => library.state).thenReturn(LibraryState(albums: albums));

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const ArtworkGridScreen(),
        ),
        GoRoute(
          path: '/album',
          builder: (_, __) => const Scaffold(body: Text('album-route')),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LibraryCubit>.value(value: library),
          BlocProvider<SettingsCubit>.value(value: settings),
        ],
        child: MaterialApp.router(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('empty state offers a rescan action wired to SettingsCubit',
      (tester) async {
    await pumpGrid(tester, const []);

    expect(find.text(l10n.artworkWall), findsOneWidget);
    expect(find.text(l10n.noAlbumsFound), findsOneWidget);

    await tester.tap(find.text(l10n.rescanLibrary));
    await tester.pump();

    verify(() => settings.rescanLibrary()).called(1);
  });

  testWidgets('populated wall renders albums and navigates on tap',
      (tester) async {
    await pumpGrid(tester, [_album(1, 'Alpha'), _album(2, 'Beta')]);

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('album-route'), findsOneWidget);
  });

  testWidgets('zoom controls change the grid column count', (tester) async {
    await pumpGrid(tester, [_album(1, 'Alpha')]);

    int columns() {
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      return delegate.crossAxisCount;
    }

    expect(columns(), 3);

    await tester.tap(find.byIcon(Icons.zoom_out_rounded));
    await tester.pump();
    expect(columns(), 4);

    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pump();
    expect(columns(), 3);
  });

  testWidgets('scrolling near the end reveals more albums', (tester) async {
    await pumpGrid(tester,
        [for (var i = 0; i < 60; i++) _album(i + 1, 'Album $i')]);

    int itemCount() {
      final grid = tester.widget<GridView>(find.byType(GridView));
      return (grid.childrenDelegate as SliverChildBuilderDelegate)
              .estimatedChildCount ??
          0;
    }

    expect(itemCount(), 50);

    await tester.drag(find.byType(GridView), const Offset(0, -12000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(itemCount(), 60);
  });
}
