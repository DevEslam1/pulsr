import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/library/presentation/widgets/smart_playlist_rule_builder.dart';
import 'package:pulsr/features/playlists/presentation/widgets/smart_playlist_card.dart';
import 'package:pulsr/features/queue/presentation/widgets/queue_slot_switcher.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

const Map<String, String> _accentMap = {
  'a': 'á',
  'e': 'é',
  'i': 'í',
  'o': 'ó',
  'u': 'ú',
  'A': 'Á',
  'E': 'É',
  'I': 'Í',
  'O': 'Ó',
  'U': 'Ú',
};

/// Transforms an English ARB template into a ~35%-expanded pseudo-localized
/// string while keeping ICU `{placeholder}` tokens intact.
String pseudoLocalizeTemplate(String source) {
  final out = StringBuffer('[');
  var braceDepth = 0;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') {
      braceDepth++;
      out.write(ch);
      continue;
    }
    if (ch == '}') {
      if (braceDepth > 0) braceDepth--;
      out.write(ch);
      continue;
    }
    if (braceDepth > 0) {
      out.write(ch);
    } else {
      final mapped = _accentMap[ch] ?? ch;
      out.write(mapped);
      if (_accentMap.containsKey(ch) && i.isEven) {
        out.write(mapped);
      }
    }
  }
  out.write(' ~]');
  return out.toString();
}

void main() {
  group('Pseudo-localization & P4 ARB completeness', () {
    test('en/ar/es ARBs have parity, non-empty values, and valid placeholders',
        () {
      final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
      final ar = jsonDecode(File('lib/l10n/app_ar.arb').readAsStringSync())
          as Map<String, dynamic>;
      final es = jsonDecode(File('lib/l10n/app_es.arb').readAsStringSync())
          as Map<String, dynamic>;

      final keys = en.keys.where((k) => !k.startsWith('@')).toList();

      for (final k in keys) {
        final enVal = en[k] as String;
        final arVal = ar[k] as String?;
        final esVal = es[k] as String?;
        expect(arVal, isNotNull, reason: 'Missing AR key: $k');
        expect(esVal, isNotNull, reason: 'Missing ES key: $k');
        expect(enVal.trim(), isNotEmpty, reason: 'Empty EN value: $k');
        expect(arVal!.trim(), isNotEmpty, reason: 'Empty AR value: $k');
        expect(esVal!.trim(), isNotEmpty, reason: 'Empty ES value: $k');

        final meta = en['@$k'] as Map<String, dynamic>?;
        final declared =
            (meta?['placeholders'] as Map<String, dynamic>?)?.keys.toSet() ??
                const <String>{};
        for (final pName in declared) {
          expect(enVal, contains('{$pName'),
              reason: 'EN missing placeholder {$pName} in $k');
          expect(arVal, contains('{$pName'),
              reason: 'AR missing placeholder {$pName} in $k');
          expect(esVal, contains('{$pName'),
              reason: 'ES missing placeholder {$pName} in $k');
        }
      }
    });

    test('pseudoLocalizeTemplate expands strings without breaking placeholders',
        () {
      final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
      for (final entry in en.entries) {
        if (entry.key.startsWith('@')) continue;
        final raw = entry.value as String;
        if (raw.contains(', plural,')) continue;
        final pseudo = pseudoLocalizeTemplate(raw);
        expect(pseudo.length, greaterThanOrEqualTo(raw.length + 3),
            reason: 'Pseudo string should expand: ${entry.key}');
        final placeholders =
            RegExp(r'\{[a-zA-Z0-9_]+\}').allMatches(raw).map((m) => m.group(0));
        for (final ph in placeholders) {
          expect(pseudo, contains(ph!),
              reason: 'Placeholder $ph corrupted in ${entry.key}');
        }
      }
    });

    test('ICU plurals format accurately across en/ar/es for P4 keys', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final ar = lookupAppLocalizations(const Locale('ar'));
      final es = lookupAppLocalizations(const Locale('es'));

      expect(en.smartRuleMatchCount(0), equals('0 matches'));
      expect(en.smartRuleMatchCount(1), equals('1 match'));
      expect(en.smartRuleMatchCount(5), equals('5 matches'));

      expect(ar.smartRuleMatchCount(1), isNot(equals(ar.smartRuleMatchCount(2))));
      expect(es.smartRuleMatchCount(1), equals('1 coincidencia'));
      expect(es.smartRuleMatchCount(3), equals('3 coincidencias'));

      expect(en.losslessCountLabel(1), equals('1 Lossless'));
      expect(en.losslessCountLabel(4), equals('4 Lossless'));
      expect(en.durationHoursMinutes(1, 5), equals('1 hr 5 min'));
      expect(en.durationMinutesOnly(1), equals('1 min'));
    });

    testWidgets(
        'high-traffic P4 widgets render cleanly under RTL Arabic & 1.5x textScale',
        (tester) async {
      useScreenSize(tester, const Size(390, 844));
      final songs = [
        createTestSong(id: 1, title: 'Track One', genre: 'Rock'),
        createTestSong(id: 2, title: 'Track Two', genre: 'Jazz'),
      ];
      final playlist = PlaylistsTableData(
        id: 1,
        name: 'Recently Added',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
        isSmart: true,
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.5),
          ),
          child: MaterialApp(
            theme: AuraTheme.darkTheme,
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        QueueSlotSwitcher(
                          activeSlot: 0,
                          onSlotSelected: (_) {},
                        ),
                        const SizedBox(width: 8),
                        const QueueSlotBadge(activeSlot: 1),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 240,
                      height: 160,
                      child: SmartPlaylistCard(
                        playlist: playlist,
                        songCount: 12,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(height: 12),
                    SmartPlaylistRuleBuilder(
                      previewSongs: songs,
                      onRulesChanged: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(find.text(ar.queueSlotShort(1)), findsWidgets);
      expect(find.text(ar.smartPlaylistDescRecentlyAdded), findsOneWidget);
    });
  });
}
