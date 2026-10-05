// Shared harness for detail-screen widget tests that need a real Drift
// database (so the use-case streams are exercised end-to-end) but a stubbed
// PlayerCubit (the tile's BlocSelector only reads state/stream).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

/// A PlayerCubit stub that always reports [state] and yields no state events.
PlayerCubit stubPlayerCubit([PlayerState? state]) {
  final cubit = MockPlayerCubit();
  when(() => cubit.state).thenReturn(state ?? const PlayerState());
  when(() => cubit.stream)
      .thenAnswer((_) => const Stream<PlayerState>.empty());
  return cubit;
}

/// Wraps [child] in the minimum app scaffolding the detail screens expect:
/// Aura theme, localization delegates and a stubbed PlayerCubit provider.
Widget detailHarness({
  required Widget child,
  PlayerCubit? playerCubit,
  Size size = const Size(1024, 2000),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: true),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: _Harness(playerCubit: playerCubit, child: child),
    ),
  );
}

class _Harness extends StatelessWidget {
  const _Harness({required this.child, this.playerCubit});

  final Widget child;
  final PlayerCubit? playerCubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PlayerCubit>.value(
      value: playerCubit ?? stubPlayerCubit(),
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }
}
