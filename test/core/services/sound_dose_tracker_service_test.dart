import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/services/sound_dose_tracker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PulsrChannels.audioEffects);
  final calls = <MethodCall>[];
  double nativeDose = 0.0;
  bool nativeAttenuating = false;

  setUp(() {
    calls.clear();
    nativeDose = 0.0;
    nativeAttenuating = false;
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getWeeklyDose':
          return nativeDose;
        case 'isSafetyAttenuationActive':
          return nativeAttenuating;
        case 'resetWeeklyDose':
          nativeDose = 0.0;
          return true;
        case 'setHeadphoneSafetyParams':
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('budget normalization', () {
    test('snaps arbitrary values onto a supported tier', () {
      expect(SoundDoseTrackerService.normalizeBudget(0.26), 0.25);
      expect(SoundDoseTrackerService.normalizeBudget(0.62), 0.5);
      expect(SoundDoseTrackerService.normalizeBudget(0.9), 1.0);
      expect(SoundDoseTrackerService.normalizeBudget(1.0), 1.0);
    });

    // A 0 budget would leave the listener permanently attenuated and a >1 budget
    // could never engage, so neither may survive normalization.
    test('refuses zero, negative and above-reference budgets', () {
      expect(SoundDoseTrackerService.normalizeBudget(0.0),
          SoundDoseTrackerService.minBudget);
      expect(SoundDoseTrackerService.normalizeBudget(-5.0),
          SoundDoseTrackerService.minBudget);
      expect(SoundDoseTrackerService.normalizeBudget(99.0),
          SoundDoseTrackerService.maxBudget);
      expect(SoundDoseTrackerService.normalizeBudget(double.nan),
          SoundDoseTrackerService.defaultBudget);
      expect(SoundDoseTrackerService.normalizeBudget(double.infinity),
          SoundDoseTrackerService.defaultBudget);
    });
  });

  group('budget arithmetic', () {
    test('used fraction is relative to the chosen budget, not the reference',
        () {
      expect(
          SoundDoseTrackerService.budgetUsedFraction(
              weeklyDose: 0.25, budget: 0.25),
          closeTo(1.0, 0.0001));
      expect(
          SoundDoseTrackerService.budgetUsedFraction(
              weeklyDose: 0.125, budget: 0.25),
          closeTo(0.5, 0.0001));
      // Same dose against the full reference is only a quarter spent.
      expect(
          SoundDoseTrackerService.budgetUsedFraction(
              weeklyDose: 0.25, budget: 1.0),
          closeTo(0.25, 0.0001));
    });

    test('a zero or negative dose reads as nothing used', () {
      expect(
          SoundDoseTrackerService.budgetUsedFraction(
              weeklyDose: 0.0, budget: 0.5),
          0.0);
      expect(
          SoundDoseTrackerService.budgetUsedFraction(
              weeklyDose: -3.0, budget: 0.5),
          0.0);
      expect(
          SoundDoseTrackerService.budgetUsedFraction(
              weeklyDose: double.nan, budget: 0.5),
          0.0);
    });

    test('engagement matches the native comparison (dose >= threshold)', () {
      expect(
          SoundDoseTrackerService.isLimitEngaged(weeklyDose: 0.5, budget: 0.5),
          isTrue);
      expect(
          SoundDoseTrackerService.isLimitEngaged(weeklyDose: 0.49, budget: 0.5),
          isFalse);
    });
  });

  group('quiet time until release', () {
    test('returns null when the limit is not engaged', () {
      expect(
          SoundDoseTrackerService.quietTimeUntilClear(
              weeklyDose: 0.30, budget: 0.5),
          isNull);
    });

    // The native stage releases at 95% of its threshold with a 7-day
    // exponential decay, so time-to-clear is tau * ln(dose / releasePoint).
    test('matches the native decay constant and release hysteresis', () {
      final expectedSeconds = SoundDoseTrackerService.decayTauSeconds *
          math.log(1.0 / SoundDoseTrackerService.releaseFraction);
      final computed = SoundDoseTrackerService.quietTimeUntilClear(
        weeklyDose: 1.0,
        budget: 1.0,
      );
      expect(computed, isNotNull);
      expect(computed!.inSeconds.toDouble(), closeTo(expectedSeconds, 1.0));
      // Sanity: a full reference dose needs hours, not seconds or weeks.
      expect(computed.inMinutes, greaterThan(60));
      expect(computed.inHours, lessThan(24));
    });

    test('a tighter budget does not change how long the dose itself decays',
        () {
      final atHalf = SoundDoseTrackerService.quietTimeUntilClear(
        weeklyDose: 0.5,
        budget: 0.5,
      );
      final atFull = SoundDoseTrackerService.quietTimeUntilClear(
        weeklyDose: 1.0,
        budget: 1.0,
      );
      expect(atHalf!.inSeconds, atFull!.inSeconds);
    });
  });

  group('channel and preference wiring', () {
    test('applyBudget persists the tier and passes it as the native threshold',
        () async {
      final tracker = SoundDoseTrackerService();
      await tracker.applyBudget(budget: 0.25, safetyEnabled: true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(PrefsKeys.audioDoseBudget), 0.25);

      final applied =
          calls.firstWhere((c) => c.method == 'setHeadphoneSafetyParams');
      expect(applied.arguments['doseThreshold'], 0.25);
      expect(applied.arguments['enabled'], isTrue);
      expect(applied.arguments['safetyCeilingDb'],
          SoundDoseTrackerService.safetyCeilingDb);
    });

    test('applyBudget normalizes before writing, so no bogus tier persists',
        () async {
      final tracker = SoundDoseTrackerService();
      await tracker.applyBudget(budget: 0.0, safetyEnabled: true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(PrefsKeys.audioDoseBudget),
          SoundDoseTrackerService.minBudget);
    });

    test('applyPersistedState leaves protection off when never chosen', () async {
      final tracker = SoundDoseTrackerService();
      await tracker.applyPersistedState();

      final applied =
          calls.firstWhere((c) => c.method == 'setHeadphoneSafetyParams');
      expect(applied.arguments['enabled'], isFalse);
      expect(applied.arguments['doseThreshold'],
          SoundDoseTrackerService.defaultBudget);
    });

    test('applyPersistedState restores a saved budget after a restart',
        () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.headphoneSafetyEnabled: true,
        PrefsKeys.audioDoseBudget: 0.5,
      });

      final tracker = SoundDoseTrackerService();
      await tracker.applyPersistedState();

      final applied =
          calls.firstWhere((c) => c.method == 'setHeadphoneSafetyParams');
      expect(applied.arguments['enabled'], isTrue);
      expect(applied.arguments['doseThreshold'], 0.5);
    });

    test('read reflects native dose and attenuation', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.audioDoseBudget: 0.5,
      });
      nativeDose = 0.45;
      nativeAttenuating = false;

      final snapshot = await SoundDoseTrackerService().read();
      expect(snapshot.weeklyDose, 0.45);
      expect(snapshot.budget, 0.5);
      expect(snapshot.usedFraction, closeTo(0.9, 0.0001));
      expect(snapshot.quietTimeUntilClear, isNull);

      nativeDose = 0.60;
      nativeAttenuating = true;
      final engaged = await SoundDoseTrackerService().read();
      expect(engaged.attenuationActive, isTrue);
      expect(engaged.quietTimeUntilClear, isNotNull);
    });

    test('resetDose reaches the native accumulator', () async {
      nativeDose = 1.4;
      final tracker = SoundDoseTrackerService();
      await tracker.resetDose();
      expect(calls.any((c) => c.method == 'resetWeeklyDose'), isTrue);
      expect(nativeDose, 0.0);
    });
  });
}
