import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/quran/quran_uthmani_text.dart';
import 'package:pulsr/data/repositories/quran_repository_impl.dart';

void main() {
  test('all 6236 displayed verses match the pinned Tanzil source verbatim', () {
    final bytes = File('assets/quran/uthmani.xml').readAsBytesSync();
    expect(sha256.convert(bytes).toString(),
        '8c5aeae20363a98f6963720d29fce040ca8b56a8e75f8b564c257fce7f6d0417');
    final source = utf8.decode(bytes);
    final repo = QuranRepositoryImpl();
    final surahs = RegExp(r'<sura index="(\d+)"[^>]*>([\s\S]*?)</sura>')
        .allMatches(source);
    expect(surahs.length, 114);
    var verseCount = 0;
    for (final surah in surahs) {
      final number = int.parse(surah[1]!);
      final verses = RegExp(r'<aya index="(\d+)" text="([^"]+)"')
          .allMatches(surah[2]!)
          .toList();
      final displayed = repo.getAyahsForSurah(number);
      expect(displayed.length, verses.length);
      for (var i = 0; i < verses.length; i++) {
        expect(displayed[i].ayahNumber, int.parse(verses[i][1]!));
        expect(displayed[i].textArabic, verses[i][2],
            reason: 'Surah $number, ayah ${i + 1} changed');
      }
      verseCount += verses.length;
    }
    expect(verseCount, 6236);
    expect(source, contains(tanzilCopyrightNotice));
  });
}
