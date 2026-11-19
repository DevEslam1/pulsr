// Per-DAC clock-architecture selection: stored mode, downgrade policy and the
// native render-mode mapping.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';
import 'package:pulsr/features/usb_tools/usb_stream_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UsbStreamMode', () {
    test('wire names are stable and unknown values fail to best effort', () {
      expect(UsbStreamMode.bitPerfectPull.wireName, 'bitPerfectPull');
      expect(UsbStreamMode.clockSyncAsrc.wireName, 'clockSyncAsrc');
      expect(UsbStreamMode.bestEffort.wireName, 'bestEffort');
      expect(UsbStreamMode.fromWireName('bitPerfectPull'),
          UsbStreamMode.bitPerfectPull);
      expect(UsbStreamMode.fromWireName('mystery'), UsbStreamMode.bestEffort);
      expect(UsbStreamMode.fromWireName(null), UsbStreamMode.bestEffort);
    });

    test('native codes match the C++ contract', () {
      expect(UsbStreamMode.bestEffort.nativeCode, 0);
      expect(UsbStreamMode.bitPerfectPull.nativeCode, 1);
      expect(UsbStreamMode.clockSyncAsrc.nativeCode, 2);
      expect(UsbRenderMode.fromNativeCode(2), UsbRenderMode.clockSyncAsrc);
      expect(UsbRenderMode.fromNativeCode(99), UsbRenderMode.bestEffort);
    });

    test('only the pull mode may claim bit-perfect', () {
      expect(UsbStreamMode.bitPerfectPull.claimsBitPerfect, isTrue);
      expect(UsbStreamMode.clockSyncAsrc.claimsBitPerfect, isFalse);
      expect(UsbStreamMode.bestEffort.claimsBitPerfect, isFalse);
      expect(UsbStreamMode.clockSyncAsrc.isResampled, isTrue);
    });
  });

  group('UsbStreamModePolicy', () {
    UsbStreamModeResolution resolve(
      UsbStreamMode requested, {
      bool pull = true,
      bool asrc = true,
      bool feedback = true,
    }) =>
        UsbStreamModePolicy.resolve(
          requested: requested,
          isFlagEnabled: (flag) =>
              (flag == PrefsKeys.usbPullRenderer && pull) ||
              (flag == PrefsKeys.usbClockSyncAsrc && asrc),
          feedbackPresent: feedback,
        );

    test('best effort is always available', () {
      final r = resolve(UsbStreamMode.bestEffort, pull: false, asrc: false);
      expect(r.effective, UsbStreamMode.bestEffort);
      expect(r.wasDowngraded, isFalse);
    });

    test('a disabled flag downgrades without changing the stored request', () {
      final r = resolve(UsbStreamMode.bitPerfectPull, pull: false);
      expect(r.effective, UsbStreamMode.bestEffort);
      expect(r.downgradeReason, 'flag_disabled');
      expect(r.requested, UsbStreamMode.bitPerfectPull);
    });

    test('ASRC requires a feedback endpoint', () {
      final r = resolve(UsbStreamMode.clockSyncAsrc, feedback: false);
      expect(r.effective, UsbStreamMode.bestEffort);
      expect(r.downgradeReason, 'feedback_required');
    });

    test('bit-perfect pull does not require feedback', () {
      final r = resolve(UsbStreamMode.bitPerfectPull, feedback: false);
      expect(r.effective, UsbStreamMode.bitPerfectPull);
      expect(r.wasDowngraded, isFalse);
    });
  });

  group('UsbStreamModeStore', () {
    test('round-trips per device and clears to best effort', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = UsbStreamModeStore(prefs: prefs);

      expect(store.read(0x1234, 0x5678), UsbStreamMode.bestEffort);
      expect(await store.write(0x1234, 0x5678, UsbStreamMode.bitPerfectPull),
          isTrue);
      expect(store.read(0x1234, 0x5678), UsbStreamMode.bitPerfectPull);
      // Another DAC is unaffected.
      expect(store.read(0x0a12, 0x0001), UsbStreamMode.bestEffort);

      expect(await store.clear(0x1234, 0x5678), isTrue);
      expect(store.read(0x1234, 0x5678), UsbStreamMode.bestEffort);
    });

    test('a corrupt stored value fails to best effort', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PrefsKeys.usbStreamModeKey(1, 2): 'asrc-with-typo',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(UsbStreamModeStore(prefs: prefs).read(1, 2),
          UsbStreamMode.bestEffort);
    });
  });
}
