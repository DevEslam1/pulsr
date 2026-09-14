// Settings wiring guard (defect 20-01, gap 20-1): every PrefsKeys constant
// must be referenced somewhere in lib/ outside its declaration, so no toggle
// is structurally unwired. This is a necessary but not sufficient proof of
// effect — per-key behavioural tests remain the full 10/10 bar.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Every key must be referenced either as PrefsKeys.<name> or by its raw
  // string value (legacy call sites). Pure orphans (neither form) are the
  // structurally-unwired toggles of defect 20-01. The follow-up is to migrate
  // raw-string sites to PrefsKeys constants; this test ratchets the orphan
  // count down instead of blocking on the migration.
  test('no orphan preference keys (20-01)', () {
    final keysFile = File('lib/core/constants/prefs_keys.dart');
    expect(keysFile.existsSync(), isTrue);
    // Multi-line declarations exist (value on the next line) plus 11 alias
    // constants (scrobblerLastSong = scrobblePendingSong). Resolve aliases to
    // their ultimate string literal.
    final src = keysFile.readAsStringSync();
    final litDecl =
        RegExp(r'''static const String (\w+)\s*=\s*['"]([^'"]+)['"]''', dotAll: true);
    final aliasDecl =
        RegExp(r'''static const String (\w+)\s*=\s*([A-Za-z_]\w*)\s*;''', dotAll: true);
    final names = <String, String>{};
    for (final m in litDecl.allMatches(src)) {
      names[m.group(1)!] = m.group(2)!;
    }
    for (final m in aliasDecl.allMatches(src)) {
      final alias = m.group(1)!;
      if (names.containsKey(alias)) continue;
      final target = m.group(2)!;
      final resolved = names[target];
      if (resolved != null) names[alias] = resolved;
    }
    expect(names.length, greaterThanOrEqualTo(170),
        reason: 'expected ~175 keys, found ${names.length}');
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    final orphans = <String>[];
    for (final entry in names.entries) {
      var hits = 0;
      for (final f in libFiles) {
        if (f.path.endsWith('prefs_keys.dart')) continue;
        final text = f.readAsStringSync();
        if (text.contains('PrefsKeys.${entry.key}') ||
            text.contains("'${entry.value}'") ||
            text.contains('"${entry.value}"')) {
          hits++;
          break;
        }
      }
      if (hits == 0) orphans.add('${entry.key}=${entry.value}');
    }
    // Ratchet (20-01): tranche 5 resolved all 9 orphans — 3 repointed at
    // their live stores (customAccentColor, dynamicThemingEnabled,
    // cloudSyncDocHashes), 5 dead constants removed (queueActiveSlot,
    // historyLastSongId/TimeMs, abLoopEnabled, exclusiveOffloadEnabled), and
    // mqaDecodingEnabled wired to MqaDecoderHelper via SettingsCubit.
    // The set may only stay empty: wire any new key at introduction.
    const allowedOrphans = <String>{};
    final orphanNames = orphans.map((e) => e.split('=').first).toSet();
    final unexpected = orphanNames.difference(allowedOrphans);
    final fixed = allowedOrphans.difference(orphanNames);
    expect(unexpected, isEmpty,
        reason: 'NEW orphan preference keys (wire them or extend the '
            'ratchet deliberately): ${unexpected.join(', ')}');
    expect(fixed, isEmpty,
        reason: 'These keys got wired — lower the ratchet by removing them '
            'from allowedOrphans: ${fixed.join(', ')}');
    expect(orphanNames.length, lessThanOrEqualTo(allowedOrphans.length));
  });
}
