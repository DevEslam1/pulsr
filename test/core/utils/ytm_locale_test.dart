// test/core/utils/ytm_locale_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/ytm_locale.dart';

void main() {
  group('YtmLocale.withLocaleParams', () {
    test('does not duplicate hl when only hl is present', () {
      final out =
          YtmLocale.withLocaleParams('https://music.youtube.com/?hl=ar');

      expect('hl='.allMatches(out).length, 1);
      expect(out, contains('gl='));
      expect(out, contains('hl=ar'));
    });

    test('does not duplicate gl when only gl is present', () {
      final out =
          YtmLocale.withLocaleParams('https://music.youtube.com/?gl=US');

      expect('gl='.allMatches(out).length, 1);
      expect(out, contains('gl=US'));
      expect(out, contains('hl='));
    });

    test('returns a fully parametrized URL unchanged', () {
      const url = 'https://music.youtube.com/?gl=EG&hl=en';
      expect(YtmLocale.withLocaleParams(url), url);
    });

    test('adds missing params without dropping existing ones', () {
      final out = YtmLocale.withLocaleParams(
          'https://music.youtube.com/watch?v=abc&gl=US');

      expect(out, contains('v=abc'));
      expect(out, contains('gl=US'));
      expect(out, contains('hl='));
      expect('gl='.allMatches(out).length, 1);
    });

    test('a gl= substring outside the query is not treated as a param', () {
      final out =
          YtmLocale.withLocaleParams('https://music.youtube.com/gl=path');

      expect(out, contains('?gl='));
      expect(out, contains('hl='));
    });

    test('homeUrl carries both params', () {
      final out = YtmLocale.homeUrl();
      expect(out, contains('gl='));
      expect(out, contains('hl='));
    });
  });
}
