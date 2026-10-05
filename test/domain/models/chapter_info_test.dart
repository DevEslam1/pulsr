// Value-semantics tests for the CUE chapter model.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/chapter_info.dart';

void main() {
  group('ChapterInfo', () {
    test('value equality across all fields', () {
      const a =
          ChapterInfo(index: 1, title: 'Intro', start: Duration(seconds: 5));
      const b =
          ChapterInfo(index: 1, title: 'Intro', start: Duration(seconds: 5));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs when any field changes', () {
      const a =
          ChapterInfo(index: 1, title: 'Intro', start: Duration(seconds: 5));
      expect(
          a ==
              const ChapterInfo(
                  index: 2, title: 'Intro', start: Duration(seconds: 5)),
          isFalse);
      expect(
          a ==
              const ChapterInfo(
                  index: 1, title: 'Outro', start: Duration(seconds: 5)),
          isFalse);
      expect(
          a ==
              const ChapterInfo(
                  index: 1, title: 'Intro', start: Duration(seconds: 6)),
          isFalse);
      expect(
          a ==
              const ChapterInfo(
                  index: 1,
                  title: 'Intro',
                  start: Duration(seconds: 5),
                  end: Duration(seconds: 10)),
          isFalse);
      expect(
          a ==
              const ChapterInfo(
                  index: 1,
                  title: 'Intro',
                  start: Duration(seconds: 5),
                  fileName: 'f.flac'),
          isFalse);
    });

    test('toString includes index, title and start seconds', () {
      const a =
          ChapterInfo(index: 3, title: 'Solo', start: Duration(seconds: 42));
      final s = a.toString();
      expect(s.contains('3'), isTrue);
      expect(s.contains('Solo'), isTrue);
      expect(s.contains('42'), isTrue);
    });
  });
}
