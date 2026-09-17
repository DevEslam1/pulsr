// LiveProg slider positions were session-only; this verifies they now persist
// and restore, and that corrupt/out-of-range data is rejected on restore.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('LiveProg slider values round-trip through prefs', () async {
    final manager = EqualizerManager();
    await manager.setLiveProg(true, code: '@init\nslider1 = 1;');
    await manager.setLiveProgSlider(1, 4.0);
    await manager.setLiveProgSlider(2, 7.5);
    await manager.onAppPaused();
    manager.dispose();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('setting_live_prog_sliders');
    expect(raw, isNotNull);
    expect(raw, contains('"1"'));

    final restored = EqualizerManager();
    await restored.init();
    expect(restored.liveProgSliders[1], 4.0);
    expect(restored.liveProgSliders[2], 7.5);
    restored.dispose();
  });

  test('corrupt or out-of-range stored sliders are ignored on restore', () async {
    SharedPreferences.setMockInitialValues({
      'setting_live_prog_sliders': '{"1": 3.0, "9": 2.0, "bad": 1.0}',
    });
    final manager = EqualizerManager();
    await manager.init();
    expect(manager.liveProgSliders[1], 3.0);
    expect(manager.liveProgSliders.containsKey(9), isFalse);
    expect(manager.liveProgSliders.containsKey(0), isFalse);
    manager.dispose();
  });

  test('non-JSON stored sliders do not throw on restore', () async {
    SharedPreferences.setMockInitialValues({
      'setting_live_prog_sliders': 'not json',
    });
    final manager = EqualizerManager();
    await manager.init();
    expect(manager.liveProgSliders, isEmpty);
    manager.dispose();
  });
}
