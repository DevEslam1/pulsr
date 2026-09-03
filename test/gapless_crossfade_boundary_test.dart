import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_feature_info.dart';

void main() {
  group('Gapless Crossfade Conflict Boundary (B-38)', () {
    test('returns null when crossfadeSeconds is 0.0', () {
      final conflict = AudioConflicts.gaplessBlockedByCrossfade(0.0);
      expect(conflict, isNull);
    });

    test('blocks gapless when crossfadeSeconds is greater than 0.0', () {
      final conflictSmall = AudioConflicts.gaplessBlockedByCrossfade(0.005);
      expect(conflictSmall, isNotNull);
      expect(conflictSmall, contains('gapless requires 0s'));

      final conflictOne = AudioConflicts.gaplessBlockedByCrossfade(1.0);
      expect(conflictOne, isNotNull);
      expect(conflictOne, contains('Crossfade is 1.0s'));
    });
  });
}
