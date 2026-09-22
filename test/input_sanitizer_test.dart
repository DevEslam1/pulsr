// test/input_sanitizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/input_sanitizer.dart';

void main() {
  group('InputSanitizer', () {
    test('sanitizePlaylistName trims and removes control characters', () {
      expect(InputSanitizer.sanitizePlaylistName('  My Playlist  '), 'My Playlist');
      expect(InputSanitizer.sanitizePlaylistName('My\x00Playlist\x1F'), 'MyPlaylist');
      expect(InputSanitizer.sanitizePlaylistName(''), 'Untitled Playlist');
      expect(InputSanitizer.sanitizePlaylistName('   '), 'Untitled Playlist');
    });

    test('sanitizePlaylistName caps length at 100 characters', () {
      final longName = 'A' * 150;
      final result = InputSanitizer.sanitizePlaylistName(longName);
      expect(result.length, 100);
      expect(result, 'A' * 100);
    });

    test('sanitizeSearchQuery trims and escapes regex metacharacters', () {
      expect(InputSanitizer.sanitizeSearchQuery('  hello*world?  '), r'hello\*world\?');
      expect(InputSanitizer.sanitizeSearchQuery('track (feat. artist) [2026]'), r'track \(feat\. artist\) \[2026\]');
    });

    test('isSafeRelativePath checks directory traversal and absolute prefixes', () {
      expect(InputSanitizer.isSafeRelativePath('subfolder/song.mp3'), isTrue);
      expect(InputSanitizer.isSafeRelativePath('../escape/song.mp3'), isFalse);
      expect(InputSanitizer.isSafeRelativePath('a/../../etc/passwd'), isFalse);
      expect(InputSanitizer.isSafeRelativePath('/absolute/path'), isFalse);
      expect(InputSanitizer.isSafeRelativePath(r'\windows\path'), isFalse);
      expect(InputSanitizer.isSafeRelativePath('C:/windows/path'), isFalse);
    });

    test('sanitizeFileName replaces illegal filesystem characters', () {
      expect(InputSanitizer.sanitizeFileName('song:name/test?file*.mp3'), 'song_name_test_file_.mp3');
      expect(InputSanitizer.sanitizeFileName('trailing_dots...'), 'trailing_dots');
      expect(InputSanitizer.sanitizeFileName(''), 'unnamed_file');
    });

    test('isValidCookie validates cookie header format', () {
      expect(InputSanitizer.isValidCookie('SAPISID=abc123xyz; HSID=987'), isTrue);
      expect(InputSanitizer.isValidCookie(''), isFalse);
      expect(InputSanitizer.isValidCookie('no_equal_sign_here'), isFalse);
      expect(InputSanitizer.isValidCookie('has\x00null=bad'), isFalse);
    });

    test('isValidProxyHost checks host format', () {
      expect(InputSanitizer.isValidProxyHost('127.0.0.1'), isTrue);
      expect(InputSanitizer.isValidProxyHost('localhost'), isTrue);
      expect(InputSanitizer.isValidProxyHost('proxy.example.com'), isTrue);
      expect(InputSanitizer.isValidProxyHost(''), isFalse);
      expect(InputSanitizer.isValidProxyHost('invalid..domain'), isFalse);
      expect(InputSanitizer.isValidProxyHost('proxy with space.com'), isFalse);
    });

    test('isValidProxyPort validates integer port range', () {
      expect(InputSanitizer.isValidProxyPort(8080), isTrue);
      expect(InputSanitizer.isValidProxyPort('8080'), isTrue);
      expect(InputSanitizer.isValidProxyPort(1), isTrue);
      expect(InputSanitizer.isValidProxyPort(65535), isTrue);
      expect(InputSanitizer.isValidProxyPort(0), isFalse);
      expect(InputSanitizer.isValidProxyPort(65536), isFalse);
      expect(InputSanitizer.isValidProxyPort(-1), isFalse);
      expect(InputSanitizer.isValidProxyPort('not_a_port'), isFalse);
    });
  });
}
