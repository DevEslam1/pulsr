// The crossfade position trigger used a fixed 1.5s early-fire margin. Prepare
// time (resolve + play acknowledgement + decoder settle + buffer gate) varies
// from ~20ms for a preloaded local track to seconds for a YouTube resolve, so a
// fixed margin either truncated the fade (prepare ate the margin and
// arbitrateTransition then clamped the fade to `remaining - 500ms`) or fired
// far too early. CrossfadeManager now measures it and exposes triggerMargin.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';

void main() {
  late CrossfadeManager manager;

  setUp(() => manager = CrossfadeManager());
  tearDown(() => manager.dispose());

  test('default margin covers the pre-change 1.5s floor', () {
    expect(manager.prepMsEwma, 1000.0);
    expect(manager.triggerMargin, const Duration(milliseconds: 1560));
  });

  test('a slow prepare raises the margin so the full fade still fits', () {
    // 30% weighting: 1000 * 0.7 + 2000 * 0.3 = 1300 -> +560 = 1860ms.
    manager.recordPrepDuration(const Duration(milliseconds: 2000));
    expect(manager.prepMsEwma, closeTo(1300.0, 0.001));
    expect(manager.triggerMargin, const Duration(milliseconds: 1860));

    // Sustained slow prepares converge towards prepare + 560ms.
    for (var i = 0; i < 40; i++) {
      manager.recordPrepDuration(const Duration(milliseconds: 2500));
    }
    expect(manager.prepMsEwma, closeTo(2500.0, 1.0));
    expect(manager.triggerMargin, const Duration(milliseconds: 3060));
  });

  test('a fast prepare lowers the margin but never below the 1.5s floor', () {
    for (var i = 0; i < 40; i++) {
      manager.recordPrepDuration(Duration.zero);
    }
    expect(manager.prepMsEwma, lessThan(1.0));
    expect(manager.triggerMargin, const Duration(milliseconds: 1500));
  });

  test('a pathological prepare cannot push the trigger past 4s', () {
    for (var i = 0; i < 40; i++) {
      manager.recordPrepDuration(const Duration(seconds: 30));
    }
    expect(manager.triggerMargin, const Duration(milliseconds: 4000));
  });

  test('a negative sample is ignored', () {
    manager.recordPrepDuration(const Duration(milliseconds: -500));
    expect(manager.prepMsEwma, 1000.0);
    expect(manager.triggerMargin, const Duration(milliseconds: 1560));
  });
}
