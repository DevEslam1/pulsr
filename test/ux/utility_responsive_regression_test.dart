import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/services/cloud_sync_service.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_stats_screen.dart';
import 'package:pulsr/features/settings/presentation/scrobble_stats_screen.dart';
import 'package:pulsr/features/settings/presentation/cloud_backup_dashboard_screen.dart';
import 'package:pulsr/features/player/presentation/themes/custom_theme_builder_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockLibrary extends Mock implements LibraryCubit {}

class MockPlayer extends Mock implements PlayerCubit {}

class MockSettings extends Mock implements SettingsCubit {}

class MockSync extends Mock implements CloudSyncService {}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(800, 1280),
    const Size(1280, 800)
  ]) {
    for (final locale in [
      const Locale('en'),
      const Locale('ar'),
      const Locale('es')
    ]) {
      for (final scale in [1.0, 2.0]) {
        for (final screen in ['library', 'scrobble', 'cloud', 'theme']) {
          testWidgets('$screen $size ${locale.languageCode} text $scale',
              (tester) async {
            SharedPreferences.setMockInitialValues({
              'last_scrobble_time':
                  DateTime(2026, 10, 3, 16, 22).millisecondsSinceEpoch,
              'total_scrobble_count': 12345
            });
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });
            await (FontLoader('Manrope')
                  ..addFont(rootBundle
                      .load('assets/fonts/Manrope-VariableFont_wght.ttf')))
                .load();
            await (FontLoader('MaterialIcons')
                  ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                .load();
            final library = MockLibrary();
            final player = MockPlayer();
            final settings = MockSettings();
            final sync = MockSync();
            when(() => library.state).thenReturn(const LibraryState());
            when(() => library.stream).thenAnswer((_) => const Stream.empty());
            when(() => player.state).thenReturn(const PlayerState());
            when(() => player.stream).thenAnswer((_) => const Stream.empty());
            when(() => settings.state).thenReturn(const SettingsState());
            when(() => settings.stream).thenAnswer((_) => const Stream.empty());
            when(() => sync.isFavoritesSyncEnabled)
                .thenAnswer((_) async => true);
            when(() => sync.isPlaylistsSyncEnabled)
                .thenAnswer((_) async => true);
            when(() => sync.lastSyncTime)
                .thenReturn(DateTime(2026, 10, 3, 16, 22));
            final page = switch (screen) {
              'library' => const LibraryStatsScreen(),
              'scrobble' => const ScrobbleStatsScreen(),
              'cloud' => CloudBackupDashboardScreen(syncService: sync),
              _ => const CustomThemeBuilderScreen()
            };
            await tester.pumpWidget(MultiBlocProvider(
                providers: [
                  BlocProvider<LibraryCubit>.value(value: library),
                  BlocProvider<PlayerCubit>.value(value: player),
                  BlocProvider<SettingsCubit>.value(value: settings)
                ],
                child: MaterialApp(
                    theme: AuraTheme.darkTheme,
                    locale: locale,
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: child!),
                    home: page)));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
            final list = find.byType(ListView).first;
            for (var i = 0; i < 3; i++) {
              await tester.drag(list, const Offset(0, -360));
              await tester.pump(const Duration(milliseconds: 300));
              expect(tester.takeException(), isNull);
            }
            await tester.pumpWidget(const SizedBox());
          });
        }
      }
    }
  }
}
