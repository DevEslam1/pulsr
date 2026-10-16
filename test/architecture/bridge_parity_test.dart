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

    final dartContent = dartFile.readAsStringSync();
    final kotlinContent = kotlinFile.readAsStringSync();

    // 1. Scrape Dart invoked methods
    final dartMethods = <String>{};
    final invokeMethodSingle =
        RegExp(r"_channel\s*\.\s*invokeMethod(?:<[^>]+>)?\s*\(\s*'([^']+)'");
    for (final match in invokeMethodSingle.allMatches(dartContent)) {
      final name = match.group(1)!;
      if (name != 'method' && name != 'enabled' && name != 'gains') {
        dartMethods.add(name);
      }
    }

    final invokeMethodDouble =
        RegExp(r'_channel\s*\.\s*invokeMethod(?:<[^>]+>)?\s*\(\s*"([^"]+)"');
    for (final match in invokeMethodDouble.allMatches(dartContent)) {
      final name = match.group(1)!;
      if (name != 'method' && name != 'enabled' && name != 'gains') {
        dartMethods.add(name);
      }
    }

    final nativeSetterSingle = RegExp(r"_invokeNativeSetter\s*\(\s*'([^']+)'");
    for (final match in nativeSetterSingle.allMatches(dartContent)) {
      dartMethods.add(match.group(1)!);
    }

    final nativeSetterDouble = RegExp(r'_invokeNativeSetter\s*\(\s*"([^"]+)"');
    for (final match in nativeSetterDouble.allMatches(dartContent)) {
      dartMethods.add(match.group(1)!);
    }

    // 2. Scrape Kotlin handled methods
    final kotlinMethods = <String>{};
    final lines = kotlinContent.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains('->')) {
        final prefix = trimmed.split('->').first;
        final quotedRegex = RegExp(r'"([a-zA-Z0-9_]+)"');
        for (final m in quotedRegex.allMatches(prefix)) {
          kotlinMethods.add(m.group(1)!);
        }
      } else if (trimmed.startsWith('"') && trimmed.endsWith('",')) {
        final quotedRegex = RegExp(r'"([a-zA-Z0-9_]+)"');
        for (final m in quotedRegex.allMatches(trimmed)) {
          kotlinMethods.add(m.group(1)!);
        }
      } else if (trimmed.contains('call.method == "')) {
        final quotedRegex = RegExp(r'call\.method\s*==\s*"([a-zA-Z0-9_]+)"');
        for (final m in quotedRegex.allMatches(trimmed)) {
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
    for (final m in dartCbSingle.allMatches(dartContent)) {
      dartCallbacks.add(m.group(1)!);
    }
    final dartCbDouble = RegExp(r'call\.method\s*==\s*"([^"]+)"');
    for (final m in dartCbDouble.allMatches(dartContent)) {
      dartCallbacks.add(m.group(1)!);
    }

    final missingInKotlin = dartMethods.difference(kotlinMethods);
    final missingCallbacksInDart = kotlinCallbacks.difference(dartCallbacks);

    expect(missingInKotlin, isEmpty,
        reason:
            'Dart invokes methods that have no Kotlin handler: $missingInKotlin');
    expect(missingCallbacksInDart, isEmpty,
        reason:
            'Kotlin invokes callbacks that have no Dart handler: $missingCallbacksInDart');
  });
}
