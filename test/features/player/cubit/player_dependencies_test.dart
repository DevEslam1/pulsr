// Coverage for player_dependencies.dart: default and explicit field wiring.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/cubit/player_dependencies.dart';

import '../player_test_support.dart';

void main() {
  group('PlayerDependencies', () {
    test('default constructor leaves every auxiliary service null', () {
      const deps = PlayerDependencies();
      expect(deps.settingsCubit, isNull);
      expect(deps.widgetService, isNull);
      expect(deps.scrobblerService, isNull);
      expect(deps.settingsProfilesService, isNull);
      expect(deps.deviceProfileService, isNull);
      expect(deps.hiResAudioService, isNull);
      expect(deps.smartAudioService, isNull);
      expect(deps.latencyTracker, isNull);
      expect(deps.perSongEqStore, isNull);
      expect(deps.perSongVolumeStore, isNull);
      expect(deps.songRatingStore, isNull);
      expect(deps.sponsorBlockService, isNull);
      expect(deps.quranModeService, isNull);
      expect(deps.earbudOptimizationService, isNull);
      expect(deps.lrclibService, isNull);
      expect(deps.ytmAccountService, isNull);
      expect(deps.mediaScannerService, isNull);
    });

    test('explicit values are stored and readable', () {
      final scrobbler = MockScrobblerService();
      final widget = MockWidgetService();
      final deps = PlayerDependencies(
        scrobblerService: scrobbler,
        widgetService: widget,
      );
      expect(deps.scrobblerService, same(scrobbler));
      expect(deps.widgetService, same(widget));
    });
  });
}
