import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/services/ytm_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YtmCacheManager Tests', () {
    late YtmCacheManager cacheManager;

    setUp(() {
      cacheManager = YtmCacheManager();
    });

    test('getHashForVideoId produces deterministic sha256 hash', () {
      final hash1 = cacheManager.getHashForVideoId('dQw4w9WgXcQ');
      final hash2 = cacheManager.getHashForVideoId('dQw4w9WgXcQ');
      final other = cacheManager.getHashForVideoId('some_other_id');

      expect(hash1, equals(hash2));
      expect(hash1, isNotEmpty);
      expect(hash1, isNot(equals(other)));
    });

    test('getCachedAudioFile returns null when track is not cached on disk',
        () async {
      final file =
          await cacheManager.getCachedAudioFile('non_existent_video_id_12345');
      expect(file, isNull);
    });

    test('getCacheSizeBytes returns non-negative integer', () async {
      final bytes = await cacheManager.getCacheSizeBytes();
      expect(bytes, greaterThanOrEqualTo(0));
    });
  });
}
