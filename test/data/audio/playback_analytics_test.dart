import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/playback_analytics.dart';

void main() {
  group('PlaybackAnalytics underrun healing', () {
    test('widens buffer after 3 underruns, not before', () {
      var widened = 0;
      final a =
          PlaybackAnalytics(onIncreaseBufferSizeRequested: () => widened++);
      a.recordBufferUnderrun();
      a.recordBufferUnderrun();
      expect(widened, 0);
      a.recordBufferUnderrun();
      expect(widened, 1);
    });

    test('steps quality down only after two widening rounds', () {
      var reduced = 0;
      final a = PlaybackAnalytics(onReduceQualityRequested: () => reduced++);
      for (var i = 0; i < 3; i++) {
        a.recordBufferUnderrun();
      }
      expect(reduced, 0);
      for (var i = 0; i < 3; i++) {
        a.recordBufferUnderrun();
      }
      expect(reduced, 1);
    });
  });
}
