import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/usb_hardware_volume_curve.dart';

void main() {
  const min = -90.0, max = 0.0;
  double db(double v) =>
      UsbHardwareVolumeCurve.dbFor(v, minDb: min, maxDb: max);

  test('full volume is DAC unity', () => expect(db(1.0), 0.0));
  test('half volume is the middle of the DAC real dB range',
      () => expect(db(0.5), closeTo(-45.0, 0.01)));
  test('zero hits DAC minimum', () => expect(db(0.0), min));
  test('uses the DAC full range, not an assumed -60 dB floor',
      () => expect(db(0.0001), closeTo(-89.991, 0.01)));
  test('monotonic', () {
    var prev = db(0.0);
    for (var v = 0.01; v <= 1.0; v += 0.01) {
      final d = db(v);
      expect(d, greaterThanOrEqualTo(prev));
      prev = d;
    }
  });
  test('non-finite input is treated as full volume', () => expect(db(double.nan), 0.0));
  test('respects a DAC whose range is narrower than the audible range', () {
    expect(
      UsbHardwareVolumeCurve.dbFor(0.001, minDb: -40, maxDb: -10),
      closeTo(-39.97, 0.01),
    );
  });

  test('the default spans the real min..max and a compressed range is opt-in',
      () {
    expect(UsbHardwareVolumeCurve.dbFor(0.000001, minDb: -90, maxDb: 0),
        closeTo(-90.0, 0.01));
    expect(
      UsbHardwareVolumeCurve.dbFor(0.000001, minDb: -90, maxDb: 0, rangeDb: 40),
      closeTo(-40.0, 0.01),
    );
  });
}
