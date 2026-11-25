// test/architecture/bridge_parity_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bridge Parity: Dart AudioEffectsChannel vs Kotlin AudioEffectsPlugin',
      () {
    final dartFile = File('lib/data/audio/audio_effects_channel.dart');
    final kotlinFile = File(
        'android/app/src/main/kotlin/com/pulsr/music/AudioEffectsPlugin.kt');

    expect(dartFile.existsSync(), isTrue, reason: 'Dart channel must exist');
    expect(kotlinFile.existsSync(), isTrue, reason: 'Kotlin plugin must exist');

    // Bridge methods may live in parts of the channel library (extracted for
    // the fat-file ratchet). Scrape the library and every declared part, not
    // just the entry file, or extracted methods look like Kotlin-only handlers.
    final dartContent = StringBuffer(dartFile.readAsStringSync());
    final partRegex = RegExp(r"part\s+'([^']+)'");
    for (final match in partRegex.allMatches(dartContent.toString())) {
      final partPath =
          File(dartFile.parent.path + Platform.pathSeparator + match.group(1)!);
      expect(partPath.existsSync(), isTrue,
          reason: 'declared part ${match.group(1)} must exist');
      dartContent.writeln(partPath.readAsStringSync());
    }
    final dartSource = dartContent.toString();
    final kotlinContent = kotlinFile.readAsStringSync();

    // 1. Scrape Dart invoked methods
    final dartMethods = <String>{};
    final invokeSingle = RegExp(
        r"_channel\s*\.\s*(?:invokeMethod|invokeMapMethod|invokeListMethod)(?:<[^>]+>)?\s*\(\s*'([^']+)'");
    for (final match in invokeSingle.allMatches(dartSource)) {
      final name = match.group(1)!;
      if (name != 'method' && name != 'enabled' && name != 'gains') {
        dartMethods.add(name);
      }
    }

    final invokeDouble = RegExp(
        r'_channel\s*\.\s*(?:invokeMethod|invokeMapMethod|invokeListMethod)(?:<[^>]+>)?\s*\(\s*"([^"]+)"');
    for (final match in invokeDouble.allMatches(dartSource)) {
      final name = match.group(1)!;
      if (name != 'method' && name != 'enabled' && name != 'gains') {
        dartMethods.add(name);
      }
    }

    final nativeSetterSingle = RegExp(r"_invokeNativeSetter\s*\(\s*'([^']+)'");
    for (final match in nativeSetterSingle.allMatches(dartSource)) {
      dartMethods.add(match.group(1)!);
    }

    final nativeSetterDouble = RegExp(r'_invokeNativeSetter\s*\(\s*"([^"]+)"');
    for (final match in nativeSetterDouble.allMatches(dartSource)) {
      dartMethods.add(match.group(1)!);
    }

    final grDbSingle = RegExp(r"_(?:readGrDb|readWorstGrDb)\s*\(\s*'([^']+)'");
    for (final match in grDbSingle.allMatches(dartSource)) {
      dartMethods.add(match.group(1)!);
    }

    final grDbDouble = RegExp(r'_(?:readGrDb|readWorstGrDb)\s*\(\s*"([^"]+)"');
    for (final match in grDbDouble.allMatches(dartSource)) {
      dartMethods.add(match.group(1)!);
    }

    // 2. Scrape Kotlin handled methods inside when (call.method) blocks
    final kotlinMethods = <String>{};
    bool inMethodSwitch = false;
    int braceDepth = 0;
    int switchDepth = 0;

    final lines = kotlinContent.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains('when (call.method)') ||
          trimmed.contains('when(call.method)')) {
        inMethodSwitch = true;
        switchDepth = braceDepth;
      }

      final codePart = trimmed.split('//').first;
      final openCount = '{'.allMatches(codePart).length;
      final closeCount = '}'.allMatches(codePart).length;

      if (inMethodSwitch) {
        final isTop = (braceDepth == switchDepth + 1) ||
            (openCount > 0 &&
                (braceDepth + openCount - closeCount) == switchDepth + 1);
        if (isTop) {
          if (codePart.contains('->')) {
            final prefix = codePart.split('->').first;
            final quotedRegex = RegExp(r'"([a-zA-Z0-9_]+)"');
            for (final m in quotedRegex.allMatches(prefix)) {
              kotlinMethods.add(m.group(1)!);
            }
          } else if (codePart.startsWith('"') && codePart.endsWith('",')) {
            final quotedRegex = RegExp(r'"([a-zA-Z0-9_]+)"');
            for (final m in quotedRegex.allMatches(codePart)) {
              kotlinMethods.add(m.group(1)!);
            }
          }
        }
      }

      braceDepth += openCount - closeCount;
      if (inMethodSwitch && braceDepth <= switchDepth) {
        inMethodSwitch = false;
      }

      if (codePart.contains('call.method == "')) {
        final quotedRegex = RegExp(r'call\.method\s*==\s*"([a-zA-Z0-9_]+)"');
        for (final m in quotedRegex.allMatches(codePart)) {
          kotlinMethods.add(m.group(1)!);
        }
      }
    }

    // 3. Scrape native callbacks and Dart handlers
    final kotlinCallbacks = <String>{};
    final cbRegex = RegExp(r'invokeMethod\s*\(\s*"([a-zA-Z0-9_]+)"');
    for (final m in cbRegex.allMatches(kotlinContent)) {
      kotlinCallbacks.add(m.group(1)!);
    }

    final dartCallbacks = <String>{};
    final dartCbSingle = RegExp(r"call\.method\s*==\s*'([^']+)'");
    for (final m in dartCbSingle.allMatches(dartSource)) {
      dartCallbacks.add(m.group(1)!);
    }
    final dartCbDouble = RegExp(r'call\.method\s*==\s*"([^"]+)"');
    for (final m in dartCbDouble.allMatches(dartSource)) {
      dartCallbacks.add(m.group(1)!);
    }

    final missingInKotlin = dartMethods.difference(kotlinMethods);
    final uncalledInKotlin = kotlinMethods.difference(dartMethods);
    final missingCallbacksInDart = kotlinCallbacks.difference(dartCallbacks);

    expect(missingInKotlin, isEmpty,
        reason:
            'Dart invokes methods that have no Kotlin handler: $missingInKotlin');
    expect(uncalledInKotlin, isEmpty,
        reason: 'Kotlin handlers have no Dart caller: $uncalledInKotlin');
    expect(missingCallbacksInDart, isEmpty,
        reason:
            'Kotlin invokes callbacks that have no Dart handler: $missingCallbacksInDart');
  });
}
