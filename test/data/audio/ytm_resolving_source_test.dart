// test/data/audio/ytm_resolving_source_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/ytm_resolving_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YtmResolvingSource Tests', () {
    test('instantiates with videoId and resolver closure', () {
      var resolvedCount = 0;
      final source = YtmResolvingSource(
        videoId: 'dQw4w9WgXcQ',
        resolve: ({bool forceRefresh = false}) async {
          resolvedCount++;
          return 'https://rr1---sn-example.googlevideo.com/videoplayback?expire=${DateTime.now().add(const Duration(hours: 4)).millisecondsSinceEpoch ~/ 1000}';
        },
      );

      expect(source.videoId, equals('dQw4w9WgXcQ'));
      expect(resolvedCount, equals(0));
    });
  });
}
