// test/features/assistant/assistant_query_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/assistant/assistant_query.dart';

void main() {
  group('classify', () {
    const cases = <(String, AssistantIntentKind)>[
      ('play chill mix', AssistantIntentKind.playPlaylist),
      ('Play Chill Mix', AssistantIntentKind.playPlaylist),
      ('play "Late Night"', AssistantIntentKind.playPlaylist),
      ('play the beatles', AssistantIntentKind.playPlaylist),
      ('shuffle rock', AssistantIntentKind.playPlaylist),
      ('resume last album', AssistantIntentKind.resumeLastAlbum),
      ('resume the last album', AssistantIntentKind.resumeLastAlbum),
      ('continue album', AssistantIntentKind.resumeLastAlbum),
      ('resume', AssistantIntentKind.resumeLastAlbum),
      ('play last album', AssistantIntentKind.resumeLastAlbum),
      ('shuffle favourites', AssistantIntentKind.shuffleFavorites),
      ('shuffle my favorites', AssistantIntentKind.shuffleFavorites),
      ('shuffle liked songs', AssistantIntentKind.shuffleFavorites),
      ('shuffle', AssistantIntentKind.shuffleFavorites),
      ('play the beatles radio', AssistantIntentKind.playArtistRadio),
      ('radio miles davis', AssistantIntentKind.playArtistRadio),
      ('blue in green', AssistantIntentKind.searchSongs),
      ('  Kind of Blue  ', AssistantIntentKind.searchSongs),
    ];

    for (final (input, expected) in cases) {
      test('"$input" -> ${expected.name}', () {
        expect(classify(input), expected);
      });
    }

    test('classifies a table of at least twelve distinct shapes', () {
      expect(cases.length, greaterThanOrEqualTo(12));
    });
  });

  group('parseAssistantText', () {
    test('extracts the playlist name and keeps its casing for display', () {
      final intent = parseAssistantText('Play "Late Night"');
      expect(intent.kind, AssistantIntentKind.playPlaylist);
      expect(intent.term, 'late night');
      expect(intent.display, 'Late Night');
      expect(intent.wantsShuffle, isFalse);
    });

    test('drops a leading article from the term but not from the display', () {
      final intent = parseAssistantText('play The Beatles radio');
      expect(intent.kind, AssistantIntentKind.playArtistRadio);
      expect(intent.term, 'beatles');
      expect(intent.display, 'The Beatles');
    });

    test('keeps the shuffle flag on a shuffled playlist', () {
      final intent = parseAssistantText('shuffle Rock');
      expect(intent.kind, AssistantIntentKind.playPlaylist);
      expect(intent.term, 'rock');
      expect(intent.wantsShuffle, isTrue);
    });

    test('bare text becomes a song search with collapsed whitespace', () {
      final intent = parseAssistantText('  Blue   in Green ');
      expect(intent.kind, AssistantIntentKind.searchSongs);
      expect(intent.term, 'blue in green');
      expect(intent.display, 'Blue in Green');
      expect(intent.rawText, 'Blue in Green');
    });

    test('resume carries no term', () {
      final intent = parseAssistantText('resume last album');
      expect(intent.term, isEmpty);
      expect(intent.display, isEmpty);
    });

    test('a quoted phrase keeps the inner text only', () {
      final intent = parseAssistantText('"Kind of Blue"');
      expect(intent.kind, AssistantIntentKind.searchSongs);
      expect(intent.term, 'kind of blue');
    });
  });

  group('parseAssistantText errors', () {
    test('empty text throws an empty error', () {
      expect(
        () => parseAssistantText('   '),
        throwsA(
          isA<AssistantQueryError>().having(
            (error) => error.kind,
            'kind',
            AssistantQueryErrorKind.empty,
          ),
        ),
      );
    });

    test('a command without a target is unparseable', () {
      expect(
        () => parseAssistantText('play'),
        throwsA(
          isA<AssistantQueryError>().having(
            (error) => error.kind,
            'kind',
            AssistantQueryErrorKind.unparseable,
          ),
        ),
      );
    });

    test('classify forwards the typed error', () {
      expect(() => classify(''), throwsA(isA<AssistantQueryError>()));
    });
  });

  group('normalizeTerm', () {
    test('trims, lowercases and collapses whitespace', () {
      expect(normalizeTerm('  Kind   of Blue  '), 'kind of blue');
    });

    test('strips a leading command and surrounding quotes', () {
      expect(normalizeTerm('PLAY "Kind of Blue"'), 'kind of blue');
    });

    test('strips a leading English article when a term follows', () {
      expect(normalizeTerm('The Beatles'), 'beatles');
      expect(normalizeTerm('a kind of blue'), 'kind of blue');
    });

    test('keeps a lone article, because nothing follows it', () {
      expect(normalizeTerm('The'), 'the');
      expect(normalizeTerm('A'), 'a');
    });
  });

  group('parseSearchExtras', () {
    test('reads the free-text query and keeps its casing', () {
      final request = parseSearchExtras({'QUERY': '  Miles Davis '});
      expect(request.field, AssistantExtraField.query);
      expect(request.term, 'miles davis');
      expect(request.display, 'Miles Davis');
      expect(request.mimeType, isEmpty);
    });

    test('PLAYLIST wins over QUERY', () {
      final request = parseSearchExtras({
        'PLAYLIST': 'Chill Mix',
        'QUERY': 'play something',
      });
      expect(request.field, AssistantExtraField.playlist);
      expect(request.term, 'chill mix');
      expect(request.display, 'Chill Mix');
    });

    test('concrete media fields win over the generic query', () {
      const expected = <String, AssistantExtraField>{
        'PLAYLIST': AssistantExtraField.playlist,
        'ALBUM': AssistantExtraField.album,
        'ARTIST': AssistantExtraField.artist,
        'GENRE': AssistantExtraField.genre,
        'SONG': AssistantExtraField.song,
        'TITLE': AssistantExtraField.title,
        'QUERY': AssistantExtraField.query,
      };
      for (final entry in expected.entries) {
        final extras = <String, String?>{entry.key: 'target'};
        if (entry.key != 'QUERY') extras['QUERY'] = 'ignored';
        final request = parseSearchExtras(extras);
        expect(request.field, entry.value, reason: entry.key);
        expect(request.term, 'target', reason: entry.key);
      }
    });

    test('accepts lower-case keys sent by some launchers', () {
      final request = parseSearchExtras({'query': 'blue in green'});
      expect(request.field, AssistantExtraField.query);
      expect(request.term, 'blue in green');
    });

    test('carries MIME_TYPE without using it for precedence', () {
      final request = parseSearchExtras({
        'QUERY': 'kind of blue',
        'MIME_TYPE': 'audio/mpeg',
      });
      expect(request.mimeType, 'audio/mpeg');
      expect(request.field, AssistantExtraField.query);
    });

    test('marks song and title requests as title scoped', () {
      expect(
        parseSearchExtras({'SONG': 'so what'}).isTitleScoped,
        isTrue,
      );
      expect(
        parseSearchExtras({'TITLE': 'so what'}).isTitleScoped,
        isTrue,
      );
      expect(
        parseSearchExtras({'ARTIST': 'miles davis'}).isTitleScoped,
        isFalse,
      );
    });

    test('strips a spoken "play" prefix from the query', () {
      final request = parseSearchExtras({'QUERY': 'play kind of blue'});
      expect(request.term, 'kind of blue');
      expect(request.display, 'kind of blue');
    });

    test('throws an empty error when no key carries a term', () {
      expect(
        () => parseSearchExtras({}),
        throwsA(
          isA<AssistantQueryError>().having(
            (error) => error.kind,
            'kind',
            AssistantQueryErrorKind.empty,
          ),
        ),
      );
      expect(
        () => parseSearchExtras({'QUERY': '   ', 'ALBUM': null}),
        throwsA(isA<AssistantQueryError>()),
      );
    });

    test('skips a blank higher-priority field and uses the next one', () {
      final request = parseSearchExtras({
        'PLAYLIST': '   ',
        'QUERY': 'so what',
      });
      expect(request.field, AssistantExtraField.query);
    });
  });
}
