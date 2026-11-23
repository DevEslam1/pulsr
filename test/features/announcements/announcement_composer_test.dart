// test/features/announcements/announcement_composer_test.dart
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/announcements/announcement_composer.dart';
import 'package:pulsr/features/announcements/announcement_strings.dart';
import 'package:pulsr/features/announcements/tts_engine.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  const track = AnnouncementTrack(
    title: 'Blue in Green',
    artist: 'Miles Davis',
    album: 'Kind of Blue',
    year: 1959,
    trackNumber: 3,
    discNumber: 1,
    duration: Duration(minutes: 5, seconds: 37),
  );

  group('composeAnnouncement', () {
    test('joins parts in the order the elements list gives', () {
      expect(
        composeAnnouncement(
          [AnnouncementElement.title, AnnouncementElement.artist],
          track,
        ),
        'Blue in Green, Miles Davis',
      );
      expect(
        composeAnnouncement(
          [AnnouncementElement.artist, AnnouncementElement.title],
          track,
        ),
        'Miles Davis, Blue in Green',
      );
      expect(
        composeAnnouncement(
          [
            AnnouncementElement.year,
            AnnouncementElement.title,
            AnnouncementElement.trackNumber,
          ],
          track,
        ),
        'from 1959, Blue in Green, track 3',
      );
    });

    test('omits album, year and track number when they are unknown', () {
      const sparse = AnnouncementTrack(title: 'Untitled', artist: '');
      expect(
        composeAnnouncement(AnnouncementElement.values, sparse),
        'Untitled',
      );
    });

    test('returns empty text when every requested part is missing', () {
      const sparse = AnnouncementTrack(title: '', artist: '');
      expect(
        composeAnnouncement(
          [
            AnnouncementElement.album,
            AnnouncementElement.year,
            AnnouncementElement.trackNumber,
          ],
          sparse,
        ),
        '',
      );
      expect(composeAnnouncement(const [], track), '');
    });

    test('drops the artist when it repeats the title', () {
      const selfTitled = AnnouncementTrack(
        title: 'Blue in Green',
        artist: 'blue in green',
      );
      expect(
        composeAnnouncement(
          [AnnouncementElement.title, AnnouncementElement.artist],
          selfTitled,
        ),
        'Blue in Green',
      );
    });

    test('trims surrounding whitespace before joining', () {
      const padded = AnnouncementTrack(
        title: '  Blue in Green ',
        artist: ' Miles Davis ',
      );
      expect(
        composeAnnouncement(
          [AnnouncementElement.title, AnnouncementElement.artist],
          padded,
        ),
        'Blue in Green, Miles Davis',
      );
    });

    test('truncates on a word boundary within maxLength', () {
      const long = AnnouncementTrack(
        title: 'A Very Long Track Title That Keeps Going And Going',
        artist: 'An Artist With A Name That Is Also Quite Long',
      );
      final spoken = composeAnnouncement(
        [AnnouncementElement.title, AnnouncementElement.artist],
        long,
        maxLength: 20,
      );

      expect(spoken.length, lessThanOrEqualTo(20));
      expect(spoken.endsWith('…'), isTrue);
      final body = spoken.substring(0, spoken.length - 1);
      expect(body, isNot(endsWith(' ')));
      expect(body, isNot(endsWith(',')));
      // The cut lands on a word boundary: the source continues with a space.
      expect(
        long.title.startsWith(body),
        isTrue,
        reason: 'truncated text must be a prefix of the source',
      );
      expect(long.title.substring(body.length, body.length + 1), ' ');
    });

    test('leaves text that already fits untouched', () {
      expect(
        composeAnnouncement(
          [AnnouncementElement.title, AnnouncementElement.artist],
          track,
          maxLength: 160,
        ),
        'Blue in Green, Miles Davis',
      );
    });
  });

  group('truncateOnWordBoundary', () {
    test('keeps short text and the exact limit unchanged', () {
      expect(truncateOnWordBoundary('short', 10), 'short');
      expect(truncateOnWordBoundary('exactlyten', 10), 'exactlyten');
    });

    test('never exceeds the limit when cutting', () {
      for (var limit = 2; limit <= 30; limit++) {
        final cut = truncateOnWordBoundary(
          'one two three four five six seven eight nine',
          limit,
        );
        expect(cut.length, lessThanOrEqualTo(limit), reason: 'limit $limit');
      }
    });

    test('hard-cuts a single word that cannot fit', () {
      final cut = truncateOnWordBoundary('Supercalifragilistic', 6);
      expect(cut, 'Super…');
      expect(cut.length, 6);
    });

    test('returns empty text for a non-positive limit', () {
      expect(truncateOnWordBoundary('anything', 0), '');
    });
  });

  group('H-47 & M-08 regressions', () {
    test('composes localized year and track number across en/ar/es', () {
      for (final code in ['en', 'ar', 'es']) {
        final l10n = lookupAppLocalizations(Locale(code));
        final spoken = composeAnnouncement(
          [
            AnnouncementElement.title,
            AnnouncementElement.year,
            AnnouncementElement.trackNumber,
          ],
          track,
          formatYear: (y) => AnnouncementStrings.yearLabel(y, l10n),
          formatTrackNumber: (n) =>
              AnnouncementStrings.trackNumberLabel(n, l10n),
        );
        expect(spoken, contains(l10n.annFromYear(1959)), reason: code);
        expect(spoken, contains(l10n.annTrackNumber(3)), reason: code);
      }
    });

    test('MethodChannelTtsEngine.init deduplicates concurrent calls', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('test.pulsr/tts_dedup');
      var initCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'init') {
          initCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return true;
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final engine = MethodChannelTtsEngine(channel: channel);
      await Future.wait([engine.init(), engine.init(), engine.init()]);
      expect(initCalls, 1);
    });
  });
}
