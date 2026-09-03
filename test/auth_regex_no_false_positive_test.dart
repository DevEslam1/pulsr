import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Auth URL Regex Tightening (B-49 / B-57)', () {
    bool isAuthInProgressUrl(String u) => RegExp(
          r'accounts\.google\.com/v3/signin|accounts\.google\.com/ServiceLogin|/checkpoint/|consent\.google',
          caseSensitive: false,
        ).hasMatch(u);

    test('matches real Google authentication and consent URLs', () {
      expect(
        isAuthInProgressUrl('https://accounts.google.com/v3/signin/identifier?dsh=S123'),
        isTrue,
      );
      expect(
        isAuthInProgressUrl('https://accounts.google.com/ServiceLogin?service=youtube'),
        isTrue,
      );
      expect(
        isAuthInProgressUrl('https://accounts.google.com/checkpoint/challenge'),
        isTrue,
      );
      expect(
        isAuthInProgressUrl('https://consent.google.com/m?continue=https://music.youtube.com'),
        isTrue,
      );
    });

    test('does not match regular YouTube videos or search queries containing signin', () {
      expect(
        isAuthInProgressUrl('https://music.youtube.com'),
        isFalse,
      );
      expect(
        isAuthInProgressUrl('https://youtube.com/watch?v=signin'),
        isFalse,
      );
      expect(
        isAuthInProgressUrl('https://music.youtube.com/search?q=signin+song'),
        isFalse,
      );
    });
  });
}
