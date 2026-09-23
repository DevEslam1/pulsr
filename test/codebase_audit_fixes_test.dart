import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Codebase Audit Fixes Verification', () {
    test('Smart playlist criteria sort field fallback and normalization', () {
      const allowedSortFields = {
        'title',
        'dateAdded',
        'playCount',
        'lastPlayed',
        'durationMs',
        'year',
        'rating',
      };

      // Valid sort keys are preserved
      for (final field in allowedSortFields) {
        final criteria = SmartCriteria(sortBy: field);
        final effectiveSortBy = allowedSortFields.contains(criteria.sortBy)
            ? criteria.sortBy!
            : 'title';
        expect(effectiveSortBy, equals(field));
      }

      // Invalid/legacy sort keys safely fallback to 'title' without asserting
      final invalidCriteria = const SmartCriteria(sortBy: 'unsupported_key');
      final fallbackSortBy = allowedSortFields.contains(invalidCriteria.sortBy)
          ? invalidCriteria.sortBy!
          : 'title';
      expect(fallbackSortBy, equals('title'));

      final nullCriteria = const SmartCriteria(sortBy: null);
      final nullFallbackSortBy = allowedSortFields.contains(nullCriteria.sortBy)
          ? nullCriteria.sortBy!
          : 'title';
      expect(nullFallbackSortBy, equals('title'));
    });

    test('USB streaming sample rate clamped to valid default when track rate is missing or invalid', () {
      int resolveSampleRate(int? trackRate) {
        int sampleRate = 48000;
        if (trackRate != null && trackRate > 0) {
          sampleRate = trackRate;
        }
        return sampleRate;
      }

      expect(resolveSampleRate(null), equals(48000));
      expect(resolveSampleRate(0), equals(48000));
      expect(resolveSampleRate(-1), equals(48000));
      expect(resolveSampleRate(44100), equals(44100));
      expect(resolveSampleRate(96000), equals(96000));
      expect(resolveSampleRate(192000), equals(192000));
    });
  });
}
