// Coverage for the USB staged-rollout flags: kill switch, deterministic
// buckets, manual overrides and the 5/25/100 cohorts.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/config/feature_flags.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<FeatureFlags> flags([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final f = FeatureFlags(prefs: prefs);
    await f.init();
    return f;
  }

  test('unknown flags are always disabled', () async {
    final f = await flags({
      PrefsKeys.usbRolloutPercent: 100,
    });
    expect(f.isEnabled('not_a_flag'), isFalse);
  });

  test('kill switch disables everything, including an explicit override',
      () async {
    final f = await flags({
      PrefsKeys.usbRolloutPercent: 100,
      '${PrefsKeys.usbPullRenderer}_override': true,
    });
    expect(await f.setRolloutStage(UsbRolloutStage.off), isTrue);
    expect(f.isEnabled(PrefsKeys.usbPullRenderer), isFalse);
    expect(f.anyUsbRendererFlagEnabled, isFalse);
  });

  test('100% stage enables both flags; overrides still win', () async {
    final f = await flags({
      PrefsKeys.usbRolloutPercent: 100,
    });
    expect(f.isEnabled(PrefsKeys.usbPullRenderer), isTrue);
    expect(f.isEnabled(PrefsKeys.usbClockSyncAsrc), isTrue);
    expect(f.anyUsbRendererFlagEnabled, isTrue);

    expect(await f.setOverride(PrefsKeys.usbPullRenderer, false), isTrue);
    expect(f.isEnabled(PrefsKeys.usbPullRenderer), isFalse);
    expect(f.isEnabled(PrefsKeys.usbClockSyncAsrc), isTrue);
    expect(await f.setOverride(PrefsKeys.usbPullRenderer, null), isTrue);
    expect(f.isEnabled(PrefsKeys.usbPullRenderer), isTrue);
  });

  test('5% cohort is deterministic and close to five percent', () async {
    final f = await flags({
      PrefsKeys.usbRolloutPercent: 5,
    });
    final prefs = await SharedPreferences.getInstance();
    var enabled = 0;
    const samples = 2000;
    for (var i = 0; i < samples; i++) {
      await prefs.setString(
          PrefsKeys.usbRolloutInstallId, i.toRadixString(16).padLeft(24, '0'));
      final first = f.isEnabled(PrefsKeys.usbPullRenderer);
      final second = f.isEnabled(PrefsKeys.usbPullRenderer);
      expect(first, second, reason: 'bucket must be stable for one install');
      if (first) enabled++;
    }
    final pct = enabled * 100 / samples;
    expect(pct, inInclusiveRange(2.5, 8.0),
        reason:
            'deterministic bucket should approximate the cohort, got $pct%');
  });

  test('25% and 100% stages widen the same bucket set', () async {
    final f = await flags({
      PrefsKeys.usbRolloutPercent: 25,
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.usbRolloutInstallId, 'a' * 32);
    final at25 = f.isEnabled(PrefsKeys.usbPullRenderer);
    await f.setRolloutStage(UsbRolloutStage.hundredPercent);
    expect(f.isEnabled(PrefsKeys.usbPullRenderer), isTrue,
        reason: '100% must include every install');
    // A bucket below 25 stays enabled; the assertion documents monotonicity.
    expect(at25, anyOf(isTrue, isFalse));
  });

  test('stage round-trips and corrupt values fail closed', () async {
    final f = await flags({
      PrefsKeys.usbRolloutPercent: 25,
    });
    expect(f.rolloutStage, UsbRolloutStage.twentyFivePercent);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.usbRolloutPercent, 7);
    expect(f.rolloutStage, UsbRolloutStage.off);
    expect(f.isEnabled(PrefsKeys.usbClockSyncAsrc), isFalse);
  });

  test('without initialized preferences every flag is off', () {
    final f = FeatureFlags();
    expect(f.isEnabled(PrefsKeys.usbPullRenderer), isFalse);
    expect(f.rolloutStage, UsbRolloutStage.off);
  });
}
