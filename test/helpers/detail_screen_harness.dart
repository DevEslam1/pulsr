// Shared harness for detail-screen widget tests that need a real Drift
// database (so the use-case streams are exercised end-to-end) but a stubbed
// PlayerCubit (the tile's BlocSelector only reads state/stream).
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

/// A PlayerCubit stub that always reports [state] and yields no state events.
PlayerCubit stubPlayerCubit([PlayerState? state]) {
  final cubit = MockPlayerCubit();
  when(() => cubit.state).thenReturn(state ?? const PlayerState());
  when(() => cubit.stream).thenAnswer((_) => const Stream<PlayerState>.empty());
  return cubit;
}

/// Wraps [child] in the minimum app scaffolding the detail screens expect:
/// Aura theme, localization delegates and a stubbed PlayerCubit provider.
Widget detailHarness({
  required Widget child,
  PlayerCubit? playerCubit,
  Size size = const Size(1024, 2000),
  Locale? locale,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: true),
    child: Directionality(
      textDirection:
          locale?.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: _Harness(playerCubit: playerCubit, locale: locale, child: child),
    ),
  );
}

class _Harness extends StatelessWidget {
  const _Harness({required this.child, this.playerCubit, this.locale});

  final Widget child;
  final PlayerCubit? playerCubit;
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PlayerCubit>.value(
      value: playerCubit ?? stubPlayerCubit(),
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        locale: locale,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }
}
