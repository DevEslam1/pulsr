// test/core/services/ytm_account_session_test.dart
//
// The pure, channel-free parts of the YTM session layer: the cookie-jar
// normaliser that every login path now funnels through, the signed-in check that
// decides whether a jar is worth saving, the SAPISIDHASH signer, and the
// Set-Cookie merge that keeps a rotating session alive.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';

void main() {
  group('normalizeCookieHeader', () {
    test('leaves an already-clean jar alone', () {
      const jar = 'SAPISID=abc; __Secure-3PSID=def';
      expect(YtmAccountService.normalizeCookieHeader(jar), jar);
    });

    test('strips a DevTools copy: newlines, the header name and attributes', () {
      // What "copy as cURL"/"copy value" actually puts on the clipboard.
      const pasted = '''
Cookie: SAPISID=abc; Path=/; Secure; HttpOnly
__Secure-3PSID=def; Domain=.youtube.com; Expires=Wed, 21 Oct 2026 07:28:00 GMT
''';
      final jar = YtmAccountService.normalizeCookieHeader(pasted);
      expect(jar, 'SAPISID=abc; __Secure-3PSID=def');
      expect(jar.contains('\n'), isFalse);
      expect(jar.toLowerCase().contains('path'), isFalse);
      expect(jar.toLowerCase().contains('expires'), isFalse);
    });

    test('collapses a duplicated cookie to the last value', () {
      // The native CookieManager answers for several domains at once, so the
      // same name arrives twice. Un-deduplicated, the header carried both while
      // the SAPISIDHASH was computed over whichever came first — a signature
      // belonging to an account the request was not making.
      final jar = YtmAccountService.normalizeCookieHeader(
          'SAPISID=first; __Secure-3PSID=x; SAPISID=second');
      expect(jar, 'SAPISID=second; __Secure-3PSID=x');
      expect('SAPISID='.allMatches(jar), hasLength(1));
    });

    test('keeps a value that contains = and an empty value', () {
      final jar = YtmAccountService.normalizeCookieHeader(
          'SID=a=b=c; CONSENT=; SAPISID=z');
      expect(jar, 'SID=a=b=c; CONSENT=; SAPISID=z');
    });

    test('drops junk that is not a cookie at all', () {
      expect(YtmAccountService.normalizeCookieHeader('   '), '');
      expect(YtmAccountService.normalizeCookieHeader('novalue'), '');
      expect(YtmAccountService.normalizeCookieHeader('=orphan'), '');
      expect(
          YtmAccountService.normalizeCookieHeader('two words=v; ok=1'), 'ok=1');
    });
  });

  group('looksLikeSignedInCookies', () {
    test('needs an SAPISID-family cookie and a PSID together', () {
      expect(
          YtmAccountService.looksLikeSignedInCookies(
              'SAPISID=a; __Secure-3PSID=b'),
          isTrue);
      expect(
          YtmAccountService.looksLikeSignedInCookies(
              '__Secure-3PAPISID=a; __Secure-1PSID=b'),
          isTrue);
      // One half of the pair is not a session.
      expect(YtmAccountService.looksLikeSignedInCookies('SAPISID=a'), isFalse);
      expect(YtmAccountService.looksLikeSignedInCookies('__Secure-3PSID=b'),
          isFalse);
    });

    test('is not fooled by a name appearing inside a value or by empty values',
        () {
      expect(
          YtmAccountService.looksLikeSignedInCookies(
              'X=SAPISID__Secure-3PSID; Y=1'),
          isFalse);
      expect(
          YtmAccountService.looksLikeSignedInCookies(
              'SAPISID=; __Secure-3PSID='),
          isFalse);
    });
  });

  group('buildAuthorizationHeader', () {
    test('prefers SAPISID, then 3P, then 1P, and is scheme-tagged for each', () {
      expect(
          YtmAccountService.buildAuthorizationHeader(
              'SAPISID=a; __Secure-3PAPISID=b; __Secure-1PAPISID=c'),
          startsWith('SAPISIDHASH '));
      expect(
          YtmAccountService.buildAuthorizationHeader(
              '__Secure-3PAPISID=b; __Secure-1PAPISID=c'),
          startsWith('SAPISID3PHASH '));
      expect(
          YtmAccountService.buildAuthorizationHeader('__Secure-1PAPISID=c'),
          startsWith('SAPISID1PHASH '));
      expect(YtmAccountService.buildAuthorizationHeader('CONSENT=1'), isNull);
    });

    test('is a timestamp_sha1 pair over the current second', () {
      final header =
          YtmAccountService.buildAuthorizationHeader('SAPISID=abc')!;
      final payload = header.split(' ').last;
      final parts = payload.split('_');
      expect(parts, hasLength(2));
      final stamp = int.parse(parts[0]);
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect((nowSec - stamp).abs(), lessThanOrEqualTo(5));
      expect(parts[1], hasLength(40)); // sha1 hex
    });

    test('the origin is part of the signature', () {
      // Reusing one hash across music.youtube.com and www.youtube.com is
      // rejected, which is why the re-signer reads the origin back off the
      // headers it is refreshing rather than assuming one.
      final a = YtmAccountService.buildAuthorizationHeader('SAPISID=abc',
          origin: 'https://music.youtube.com')!;
      final b = YtmAccountService.buildAuthorizationHeader('SAPISID=abc',
          origin: 'https://www.youtube.com')!;
      expect(a.split('_').last, isNot(b.split('_').last));
    });
  });

  group('splitSetCookies', () {
    test('does not break on an Expires date containing a comma', () {
      final parts = YtmAccountService.splitSetCookies(
          'A=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/, B=2; Path=/');
      expect(parts, hasLength(2));
      expect(parts.first, startsWith('A=1'));
      expect(parts.last, startsWith('B=2'));
    });
  });

  group('mergeSetCookieInto', () {
    test('rotates a value in place and keeps the rest of the jar', () {
      // Google re-issues SIDCC and the __Secure-*PSID family on ordinary
      // authenticated traffic and drops the old values when the rotation is
      // never acknowledged, so a jar that was valid at login quietly ages out.
      final merged = YtmAccountService.mergeSetCookieInto(
        'SAPISID=keep; SIDCC=old',
        'SIDCC=new; Path=/; Secure, __Secure-3PSID=fresh; Path=/',
      );
      expect(merged, contains('SAPISID=keep'));
      expect(merged, contains('SIDCC=new'));
      expect(merged, contains('__Secure-3PSID=fresh'));
      expect(merged, isNot(contains('SIDCC=old')));
    });

    test('an empty header is a no-op', () {
      expect(YtmAccountService.mergeSetCookieInto('SAPISID=a', ''),
          'SAPISID=a');
    });
  });
}
