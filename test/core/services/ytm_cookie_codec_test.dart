import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_cookie_codec.dart';

void main() {
  group('YtmCookieCodec', () {
    test('normalizeCookieHeader removes attribute names and normalizes spacing', () {
      const raw = 'SID=abc123; Path=/; Domain=.youtube.com; HSID=def456; Secure; HttpOnly';
      final normalized = YtmCookieCodec.normalizeCookieHeader(raw);
      expect(normalized, contains('SID=abc123'));
      expect(normalized, contains('HSID=def456'));
      expect(normalized, isNot(contains('Path=/')));
      expect(normalized, isNot(contains('Secure')));
    });

    test('scopeCookiesForYouTube drops account-only and __Host- cookies', () {
      const raw = 'SID=123; LSID=login456; __Host-GAPS=789; SSID=abc';
      final scoped = YtmCookieCodec.scopeCookiesForYouTube(raw);
      expect(scoped, contains('SID=123'));
      expect(scoped, contains('SSID=abc'));
      expect(scoped, isNot(contains('LSID=')));
      expect(scoped, isNot(contains('__Host-GAPS=')));
    });

    test('splitSetCookies properly splits multiple cookies even with commas in expires', () {
      const header =
          'PREF=tz=UTC; Expires=Fri, 01 Jan 2038 00:00:00 GMT; Path=/, '
          'VISITOR_INFO1_LIVE=xyz; Max-Age=31536000; Path=/; Domain=.youtube.com';
      final split = YtmCookieCodec.splitSetCookies(header);
      expect(split.length, equals(2));
      expect(split[0], startsWith('PREF=tz=UTC'));
      expect(split[1], startsWith('VISITOR_INFO1_LIVE=xyz'));
    });

    test('mergeSetCookieInto updates existing cookies and adds new ones', () {
      const jar = 'SID=old_sid; HSID=old_hsid';
      const setCookie = 'SID=new_sid; Path=/, SSID=new_ssid; Path=/';
      final merged = YtmCookieCodec.mergeSetCookieInto(jar, setCookie);
      expect(merged, contains('SID=new_sid'));
      expect(merged, contains('HSID=old_hsid'));
      expect(merged, contains('SSID=new_ssid'));
    });

    test('mergeSetCookieInto deletes expired cookies via Max-Age=0 or past Expires', () {
      const jar = 'SID=my_sid; TO_DELETE=val; EXPIRED_DATE=val2';
      const setCookie =
          'TO_DELETE=deleted; Max-Age=0; Path=/, '
          'EXPIRED_DATE=deleted; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/';
      final merged = YtmCookieCodec.mergeSetCookieInto(jar, setCookie);
      expect(merged, contains('SID=my_sid'));
      expect(merged, isNot(contains('TO_DELETE')));
      expect(merged, isNot(contains('EXPIRED_DATE')));
    });

    test('looksLikeSignedInCookies detects valid Google session combinations', () {
      // Must have at least one SAPISID family and at least one PSID family
      expect(
        YtmCookieCodec.looksLikeSignedInCookies('SAPISID=123; __Secure-3PSID=456'),
        isTrue,
      );
      expect(
        YtmCookieCodec.looksLikeSignedInCookies('__Secure-1PAPISID=123; __Secure-1PSID=456'),
        isTrue,
      );
      // Missing PSID
      expect(
        YtmCookieCodec.looksLikeSignedInCookies('SAPISID=123; OTHER=456'),
        isFalse,
      );
      // Missing SAPISID
      expect(
        YtmCookieCodec.looksLikeSignedInCookies('__Secure-3PSID=456; OTHER=123'),
        isFalse,
      );
      // Empty string
      expect(YtmCookieCodec.looksLikeSignedInCookies(''), isFalse);
    });
  });
}
