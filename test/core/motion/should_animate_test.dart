// Unit & widget tests for PulsrMotion.shouldAnimate(BuildContext).
//
// Verifies all combinations of OS MediaQuery.disableAnimations, in-app
// SettingsState.reduceMotion, reactive rebuilds on state changes, callback
// invocation outside build(), and safe fallback when SettingsCubit is absent.
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  group('PulsrMotion.shouldAnimate', () {
    testWidgets(
      'returns true when OS disableAnimations is false and in-app reduceMotion is false',
      (tester) async {
        final cubit = _MockSettingsCubit();
        when(() => cubit.state)
            .thenReturn(const SettingsState(reduceMotion: false));
        when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

        bool? result;
        bool? extResult;
        Duration? resolved;

        await tester.pumpWidget(
          BlocProvider<SettingsCubit>.value(
            value: cubit,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: false),
              child: Builder(
                builder: (context) {
                  result = PulsrMotion.shouldAnimate(context);
                  extResult = context.shouldAnimate;
                  resolved = context.motion(PulsrMotion.page);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(result, isTrue);
        expect(extResult, isTrue);
        expect(resolved, PulsrMotion.page);
      },
    );

    testWidgets(
      'returns false when OS disableAnimations is true even if in-app reduceMotion is false',
      (tester) async {
        final cubit = _MockSettingsCubit();
        when(() => cubit.state)
            .thenReturn(const SettingsState(reduceMotion: false));
        when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

        bool? result;
        Duration? resolved;

        await tester.pumpWidget(
          BlocProvider<SettingsCubit>.value(
            value: cubit,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Builder(
                builder: (context) {
                  result = PulsrMotion.shouldAnimate(context);
                  resolved = context.motion(PulsrMotion.page);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(result, isFalse);
        expect(resolved, Duration.zero);
      },
    );

    testWidgets(
      'returns false when in-app reduceMotion is true even if OS disableAnimations is false',
      (tester) async {
        final cubit = _MockSettingsCubit();
        when(() => cubit.state)
            .thenReturn(const SettingsState(reduceMotion: true));
        when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

        bool? result;
        bool? enabled;
        Duration? resolved;

        await tester.pumpWidget(
          BlocProvider<SettingsCubit>.value(
            value: cubit,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: false),
              child: Builder(
                builder: (context) {
                  result = PulsrMotion.shouldAnimate(context);
                  enabled = PulsrMotion.isEnabled(context);
                  resolved = context.motion(PulsrMotion.ambient);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(result, isFalse);
        expect(enabled, isFalse);
        expect(resolved, Duration.zero);
      },
    );

    testWidgets(
      'returns false when both OS disableAnimations and in-app reduceMotion are true',
      (tester) async {
        final cubit = _MockSettingsCubit();
        when(() => cubit.state)
            .thenReturn(const SettingsState(reduceMotion: true));
        when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

        bool? result;

        await tester.pumpWidget(
          BlocProvider<SettingsCubit>.value(
            value: cubit,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Builder(
                builder: (context) {
                  result = PulsrMotion.shouldAnimate(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(result, isFalse);
      },
    );

    testWidgets(
      'rebuilds reactively when SettingsCubit toggles reduceMotion',
      (tester) async {
        final cubit = _MockSettingsCubit();
        final controller = StreamController<SettingsState>.broadcast();
        addTearDown(controller.close);

        var current = const SettingsState(reduceMotion: false);
        when(() => cubit.state).thenAnswer((_) => current);
        when(() => cubit.stream).thenAnswer((_) => controller.stream);

        bool? latest;

        await tester.pumpWidget(
          BlocProvider<SettingsCubit>.value(
            value: cubit,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: false),
              child: Builder(
                builder: (context) {
                  latest = PulsrMotion.shouldAnimate(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        expect(latest, isTrue);

        current = const SettingsState(reduceMotion: true);
        controller.add(current);
        await tester.pumpAndSettle();
        expect(latest, isFalse);

        current = const SettingsState(reduceMotion: false);
        controller.add(current);
        await tester.pumpAndSettle();
        expect(latest, isTrue);
      },
    );

    testWidgets(
      'falls back safely to !MediaQuery.disableAnimationsOf when SettingsCubit is absent',
      (tester) async {
        bool? allowedWithoutProvider;
        bool? disabledWithoutProvider;

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: false),
            child: Builder(
              builder: (context) {
                allowedWithoutProvider = PulsrMotion.shouldAnimate(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(allowedWithoutProvider, isTrue);

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                disabledWithoutProvider = PulsrMotion.shouldAnimate(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(disabledWithoutProvider, isFalse);
      },
    );

    testWidgets(
      'works safely when called from an event callback outside build()',
      (tester) async {
        final cubit = _MockSettingsCubit();
        when(() => cubit.state)
            .thenReturn(const SettingsState(reduceMotion: true));
        when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

        bool? callbackResult;

        await tester.pumpWidget(
          BlocProvider<SettingsCubit>.value(
            value: cubit,
            child: MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(disableAnimations: false),
                child: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      callbackResult = PulsrMotion.shouldAnimate(context);
                    },
                    child: const Text('Check'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Check'));
        await tester.pump();
        expect(callbackResult, isFalse);
      },
    );
  });
}
