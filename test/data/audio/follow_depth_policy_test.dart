// test/data/audio/follow_depth_policy_test.dart
//
// Locks the rule that an unread track bit depth is not a 16-bit track. The
// exclusive path used to fall back to PlayerConstants.defaultBitDepth (16),
// which silently narrowed a 24-bit file whose metadata was never read.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/output_format_negotiation.dart';

void main() {
  group('resolveFollowBitDepth', () {
    test('the track depth always wins over the route', () {
      expect(resolveFollowBitDepth(trackBitDepth: 16, deviceBitDepth: 32), 16);
      expect(resolveFollowBitDepth(trackBitDepth: 24, deviceBitDepth: 16), 24);
      expect(resolveFollowBitDepth(trackBitDepth: 32, deviceBitDepth: 24), 32);
    });

    test('an unread depth follows the live direct stream', () {
      expect(
        resolveFollowBitDepth(
          trackBitDepth: 0,
          streamingBitDepth: 24,
          deviceBitDepth: 16,
        ),
        24,
      );
    });

    test('an unread depth follows the advertised device depth', () {
      expect(resolveFollowBitDepth(trackBitDepth: 0, deviceBitDepth: 32), 32);
      expect(resolveFollowBitDepth(trackBitDepth: 0, deviceBitDepth: 16), 16);
    });

    test('nothing known defaults to 24-bit, never 16', () {
      expect(resolveFollowBitDepth(trackBitDepth: 0), 24);
      expect(
        resolveFollowBitDepth(trackBitDepth: -1, deviceBitDepth: 12),
        24,
      );
    });

    test('invalid negative inputs are ignored', () {
      expect(
        resolveFollowBitDepth(
          trackBitDepth: -24,
          streamingBitDepth: -1,
          deviceBitDepth: 24,
        ),
        24,
      );
    });
  });
}
