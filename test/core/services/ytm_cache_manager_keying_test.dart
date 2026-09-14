// test/core/services/ytm_cache_manager_keying_test.dart
//
// F9 regression. The in-memory URL cache was always quality-keyed, but the
// on-disk body cache was keyed on the video id alone, so a body cached for one
// streaming quality could be served for another.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_cache_manager.dart';

void main() {
  group('YtmCacheManager - quality-keyed disk slots (F9)', () {
    const hash = 'abc123';

    test('high keeps the historical un-keyed name', () {
      expect(YtmCacheManager.cacheFileName(hash, 'high', 'm4a'),
          equals('$hash.m4a'));
      expect(YtmCacheManager.cacheFileName(hash, 'HIGH', 'webm'),
          equals('$hash.webm'));
      expect(YtmCacheManager.cacheFileName(hash, '', 'm4a'),
          equals('$hash.m4a'));
    });

    test('other qualities get their own slot', () {
      expect(YtmCacheManager.cacheFileName(hash, 'low', 'm4a'),
          equals('$hash.low.m4a'));
      expect(YtmCacheManager.cacheFileName(hash, 'medium', 'webm'),
          equals('$hash.medium.webm'));
      expect(
          YtmCacheManager.cacheFileName(hash, 'low', 'm4a'),
          isNot(equals(
              YtmCacheManager.cacheFileName(hash, 'high', 'm4a'))));
    });

    test('the cleanup sweep covers every quality and container', () {
      final names = YtmCacheManager.allCacheFileNames(hash);
      for (final ext in YtmCacheManager.allCacheExtensions) {
        expect(names, contains('$hash.$ext'), reason: 'legacy/high $ext');
        for (final q in YtmCacheManager.cacheQualities) {
          expect(names, contains('$hash.$q.$ext'));
        }
      }
      expect(names,
          contains(YtmCacheManager.cacheFileName(hash, 'low', 'webm')));
    });
  });
}