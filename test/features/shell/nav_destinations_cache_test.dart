import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/shell/presentation/nav_destinations.dart';

void main() {
  tearDown(debugClearNavDestinationsCache);

  test('destination cache evicts beyond its locale bound', () {
    const destinations = <PulsrDestination>[
      PulsrDestination(
        index: 0,
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: 'Home',
      ),
    ];

    for (var i = 0; i < 12; i++) {
      debugSeedNavDestinationsCache(Locale('l$i'), destinations);
    }

    expect(debugNavDestinationsCacheSize, lessThanOrEqualTo(4));
  });

  test('re-seeding a cached locale does not grow the map', () {
    const destinations = <PulsrDestination>[];
    const locale = Locale('en');
    debugSeedNavDestinationsCache(locale, destinations);
    debugSeedNavDestinationsCache(locale, destinations);
    expect(debugNavDestinationsCacheSize, 1);
  });
}
