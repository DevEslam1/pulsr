// test/ytm_cookie_session_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';

void main() {
  group('YtmAccountService.looksLikeSignedInCookies', () {
    test('accepts classic SAPISID + __Secure-3PSID session', () {
      const raw = 'SID=g.a000; SAPISID=abc123; __Secure-3PSID=xyz789';
      expect(YtmAccountService.looksLikeSignedInCookies(raw), isTrue);
    });

    test('accepts secure-variant combinations', () {
      const raw =
          '__Secure-3PAPISID=tok; __Secure-1PSID=tok2; LOGIN_INFO=x';
      expect(YtmAccountService.looksLikeSignedInCookies(raw), isTrue);
    });

    test('rejects when the PSID family is missing', () {
      const raw = 'SID=g.a000; SAPISID=abc123';
      expect(YtmAccountService.looksLikeSignedInCookies(raw), isFalse);
    });

    test('rejects when only PSID present without any APISID/SAPISID', () {
      const raw = '__Secure-3PSID=xyz789; SID=g.a000';
      expect(YtmAccountService.looksLikeSignedInCookies(raw), isFalse);
    });

    test('is not fooled by cookie names appearing inside other values', () {
      // The old substring check (raw.contains('SAPISID')) passed this.
      const raw = 'VISITOR_INFO1_LIVE=xxSAPISIDxx; YSC=__Secure-3PSIDjunk';
      expect(YtmAccountService.looksLikeSignedInCookies(raw), isFalse);
    });

    test('rejects empty-valued session cookies', () {
      const raw = 'SAPISID=; __Secure-3PSID=';
      expect(YtmAccountService.looksLikeSignedInCookies(raw), isFalse);
    });

    test('matches names exactly, not as prefixes', () {
      const raw = 'XSAPISIDABC=v; X__Secure-3PSIDXYZ=w';
      expect(YtmAccountService.looksLikeSignedInCookies(raw), isFalse);
    });

    test('handles empty input', () {
      expect(YtmAccountService.looksLikeSignedInCookies(''), isFalse);
    });
  });

  group('YtmAccountService.mergeSetCookieInto', () {
    test('does not split on Expires-date commas', () {
      final out = YtmAccountService.mergeSetCookieInto(
        'A=1',
        'B=2; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/; Secure',
      );
      expect(out, contains('A=1'));
      expect(out, contains('B=2'));
      // No phantom cookies from the date fragment.
      expect(out.contains('21 Oct'), isFalse,
          reason: 'date fragment must not become a cookie name');
      expect(out.split('; ').length, 2);
    });

    test('does not split on old dashed Expires dates either', () {
      final out = YtmAccountService.mergeSetCookieInto(
        '',
        'F=5; expires=Wed, 21-Oct-2026 07:28:00 GMT; Secure',
      );
      expect(out, 'F=5');
    });

    test('splits real comma-merged Set-Cookie headers', () {
      final out = YtmAccountService.mergeSetCookieInto(
        '',
        'C=3; Path=/, D=4; HttpOnly',
      );
      expect(out, contains('C=3'));
      expect(out, contains('D=4'));
    });

    test('overwrites existing values', () {
      final out = YtmAccountService.mergeSetCookieInto(
        'A=old; KEEP=yes',
        'A=new; Path=/',
      );
      expect(out, contains('A=new'));
      expect(out.contains('A=old'), isFalse);
      expect(out, contains('KEEP=yes'));
    });

    test('preserves base64 padding inside values', () {
      final out = YtmAccountService.mergeSetCookieInto(
        '',
        'E=abc==; Path=/',
      );
      expect(out, 'E=abc==');
    });

    test('drops attribute parts and keeps only name=value pairs', () {
      final out = YtmAccountService.mergeSetCookieInto(
        '',
        'G=6; Domain=.youtube.com; Path=/; HttpOnly; SameSite=None',
      );
      expect(out, 'G=6');
    });
  });

  group('YtmWebLoginSheet URL classification', () {
    final isCookieMismatchUrl = RegExp(
      r'CookieMismatch|/sorry|speedbump',
      caseSensitive: false,
    );
    final isAuthInProgressUrl = RegExp(
      r'accounts\.google\.com|ServiceLogin|signin|/checkpoint/|consent\.',
      caseSensitive: false,
    );

    test('matches CookieMismatch and block error page URLs', () {
      expect(
        isCookieMismatchUrl.hasMatch('https://accounts.google.com/CookieMismatch?continue=...'),
        isTrue,
      );
      expect(
        isCookieMismatchUrl.hasMatch('https://music.youtube.com/sorry/index?continue=...'),
        isTrue,
      );
    });

    test('matches Google Sign-In and consent URLs without classifying them as mismatch', () {
      expect(
        isAuthInProgressUrl.hasMatch('https://accounts.google.com/ServiceLogin?service=youtube'),
        isTrue,
      );
      expect(
        isCookieMismatchUrl.hasMatch('https://accounts.google.com/ServiceLogin?service=youtube'),
        isFalse,
      );
      expect(
        isAuthInProgressUrl.hasMatch('https://accounts.google.com/v3/signin/identifier'),
        isTrue,
      );
      expect(
        isCookieMismatchUrl.hasMatch('https://accounts.google.com/v3/signin/identifier'),
        isFalse,
      );
    });

    test('does not match normal YouTube Music browsing URLs', () {
      expect(isCookieMismatchUrl.hasMatch('https://music.youtube.com/'), isFalse);
      expect(isAuthInProgressUrl.hasMatch('https://music.youtube.com/'), isFalse);
      expect(isCookieMismatchUrl.hasMatch('https://music.youtube.com/library'), isFalse);
      expect(isCookieMismatchUrl.hasMatch('https://music.youtube.com/explore'), isFalse);
      expect(isCookieMismatchUrl.hasMatch('https://music.youtube.com/playlist?list=LM'), isFalse);
    });
  });

  group('YtmAccountService.buildAuthorizationHeader', () {
    test('builds SAPISIDHASH when SAPISID is present', () {
      final header = YtmAccountService.buildAuthorizationHeader('SAPISID=test_sapisid_123; __Secure-3PSID=psid');
      expect(header, isNotNull);
      expect(header!.startsWith('SAPISIDHASH '), isTrue);
    });

    test('builds SAPISID3PHASH when only __Secure-3PAPISID is present', () {
      final header = YtmAccountService.buildAuthorizationHeader('__Secure-3PAPISID=test_3papisid_456; __Secure-3PSID=psid');
      expect(header, isNotNull);
      expect(header!.startsWith('SAPISID3PHASH '), isTrue);
    });

    test('builds SAPISID1PHASH when only __Secure-1PAPISID is present', () {
      final header = YtmAccountService.buildAuthorizationHeader('__Secure-1PAPISID=test_1papisid_789; __Secure-1PSID=psid');
      expect(header, isNotNull);
      expect(header!.startsWith('SAPISID1PHASH '), isTrue);
    });

    test('returns null when no APISID cookie is present', () {
      final header = YtmAccountService.buildAuthorizationHeader('__Secure-3PSID=psid; OTHER=123');
      expect(header, isNull);
    });
  });
}
