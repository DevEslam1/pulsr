// test/core/services/ytm_account_service_parsing_test.dart
//
// Pure, channel-free parsing and serialization of the YTM account layer:
// the account-playlist model, cookie scoping, Set-Cookie deletion semantics
// and the remaining normalization edges not covered by
// ytm_account_session_test.dart.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';

void main() {
  group('YtmAccountPlaylist', () {
    test('cleanPlaylistId strips a single VL prefix only', () {
      expect(
        const YtmAccountPlaylist(
          playlistId: 'VLPLabc',
          title: 't',
          subtitle: 's',
        ).cleanPlaylistId,
        'PLabc',
      );
      expect(
        const YtmAccountPlaylist(
          playlistId: 'PLabc',
          title: 't',
          subtitle: 's',
        ).cleanPlaylistId,
        'PLabc',
      );
      expect(
        const YtmAccountPlaylist(
          playlistId: 'VLLM',
          title: 't',
          subtitle: 's',
        ).cleanPlaylistId,
        'LM',
      );
    });

    test('shareUrl is built from the cleaned id', () {
      const playlist = YtmAccountPlaylist(
        playlistId: 'VLPLabc',
        title: 't',
        subtitle: 's',
      );
      expect(
        playlist.shareUrl,
        'https://music.youtube.com/playlist?list=PLabc',
      );
    });

    test('toJson/fromJson round-trips and fills defaults', () {
      const playlist = YtmAccountPlaylist(
        playlistId: 'PLabc',
        title: 'My Mix',
        subtitle: '12 songs',
        artworkUrl: 'https://example.com/a.jpg',
      );
      final restored = YtmAccountPlaylist.fromJson(
        jsonDecode(jsonEncode(playlist.toJson())) as Map<String, dynamic>,
      );
      expect(restored.playlistId, 'PLabc');
      expect(restored.title, 'My Mix');
      expect(restored.subtitle, '12 songs');
      expect(restored.artworkUrl, 'https://example.com/a.jpg');

      final empty = YtmAccountPlaylist.fromJson(const {});
      expect(empty.playlistId, isEmpty);
      expect(empty.title, 'Playlist');
      expect(empty.subtitle, 'YouTube Music');
      expect(empty.artworkUrl, isNull);
    });
  });

  group('scopeCookiesForYouTube', () {
    test('drops Google account-only cookies and __Host- cookies', () {
      const raw = 'SAPISID=keep; LSID=drop; __Secure-3PSID=keep2; '
          'ACCOUNT_CHOOSER=drop2; __Host-GAPS=drop3; NID=drop4';
      expect(
        YtmAccountService.scopeCookiesForYouTube(raw),
        'SAPISID=keep; __Secure-3PSID=keep2',
      );
    });

    test('is case-sensitive for the account blocklist, like a browser', () {
      // Only exact Google cookie names are account-scoped; a lower-case 'nid'
      // is a different cookie and must survive.
      expect(
        YtmAccountService.scopeCookiesForYouTube('nid=keep; NID=drop'),
        'nid=keep',
      );
    });

    test('normalizes and dedupes before scoping', () {
      const pasted = '''
Cookie: SAPISID=first; Path=/; Secure
__Secure-3PSID=psid; SAPISID=second; Domain=.youtube.com
''';
      expect(
        YtmAccountService.scopeCookiesForYouTube(pasted),
        'SAPISID=second; __Secure-3PSID=psid',
      );
    });

    test('empty or junk input scopes to an empty jar', () {
      expect(YtmAccountService.scopeCookiesForYouTube(''), isEmpty);
      expect(YtmAccountService.scopeCookiesForYouTube('  '), isEmpty);
      expect(YtmAccountService.scopeCookiesForYouTube('no-equals'), isEmpty);
    });
  });

  group('buildAuthorizationHeader - value handling', () {
    test('a value containing = is hashed whole', () {
      final header =
          YtmAccountService.buildAuthorizationHeader('SAPISID=a=b=c')!;
      final stamp = header.split(' ').last.split('_').first;
      final expected = sha1
          .convert(utf8.encode('$stamp a=b=c https://music.youtube.com'))
          .toString();
      expect(header, 'SAPISIDHASH ${stamp}_$expected');
    });

    test('an empty SAPISID falls through to the 3P variant', () {
      final header = YtmAccountService.buildAuthorizationHeader(
          'SAPISID=; __Secure-3PAPISID=b')!;
      expect(header, startsWith('SAPISID3PHASH '));
    });
  });

  group('mergeSetCookieInto - deletion semantics', () {
    test('Max-Age=0 and a negative Max-Age delete the cookie', () {
      final a = YtmAccountService.mergeSetCookieInto(
          'A=1; KEEP=y', 'A=gone; Max-Age=0');
      expect(a, 'KEEP=y');
      final b = YtmAccountService.mergeSetCookieInto(
          'B=2; KEEP=y', 'B=gone; Max-Age=-1');
      expect(b, 'KEEP=y');
    });

    test('an Expires date in the past deletes the cookie', () {
      final merged = YtmAccountService.mergeSetCookieInto(
        'SIDCC=old; KEEP=y',
        'SIDCC=; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
      );
      expect(merged, 'KEEP=y');
    });

    test('a future Expires date keeps the new value', () {
      final merged = YtmAccountService.mergeSetCookieInto(
        'SIDCC=old',
        'SIDCC=new; Expires=Wed, 21 Oct 2099 07:28:00 GMT',
      );
      expect(merged, 'SIDCC=new');
    });

    test('an unparseable Expires is ignored, not treated as expiry', () {
      final merged = YtmAccountService.mergeSetCookieInto(
        'SIDCC=old',
        'SIDCC=new; Expires=not-a-date',
      );
      expect(merged, 'SIDCC=new');
    });

    test('segments without = and empty headers are skipped', () {
      expect(YtmAccountService.mergeSetCookieInto('', 'broken'), '');
      expect(YtmAccountService.mergeSetCookieInto('=orphan', 'A=1'), 'A=1');
      expect(YtmAccountService.mergeSetCookieInto('', '; ; '), '');
    });

    test('deleting a cookie that is not in the jar is a no-op', () {
      expect(
        YtmAccountService.mergeSetCookieInto('A=1', 'B=2; Max-Age=0'),
        'A=1',
      );
    });

    test('keeps padding and equals signs inside values', () {
      final merged = YtmAccountService.mergeSetCookieInto(
        'A=1',
        'B=abc==; Path=/, C=x=y; Secure',
      );
      expect(merged, contains('B=abc=='));
      expect(merged, contains('C=x=y'));
    });
  });

  group('splitSetCookies - additional edges', () {
    test('an empty header yields nothing', () {
      expect(YtmAccountService.splitSetCookies(''), isEmpty);
      expect(YtmAccountService.splitSetCookies('   '), isEmpty);
    });

    test('a comma inside a non-cookie fragment is not a split point', () {
      // Next part has no '=' before its ';' so the comma is a value character.
      final parts =
          YtmAccountService.splitSetCookies('A=1, plain text; Path=/');
      expect(parts, hasLength(1));
      expect(parts.single, 'A=1, plain text; Path=/');
    });

    test('three comma-merged cookies all survive', () {
      final parts =
          YtmAccountService.splitSetCookies('A=1; Path=/, B=2; Path=/, C=3');
      expect(parts, hasLength(3));
      expect(parts[0], startsWith('A=1'));
      expect(parts[1], startsWith('B=2'));
      expect(parts[2], startsWith('C=3'));
    });
  });
}
