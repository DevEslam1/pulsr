import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the generated dependency graph.
///
/// `configureDependencies()` cannot run under `flutter_test` because eager
/// singletons reach for platform channels (`AppDatabase` via path_provider,
/// `PulsrAudioHandler` via audio_service). Injectable only *warns* about an
/// unresolvable dependency, and `gh.singleton` instantiates immediately, so a
/// missing registration is a launch-time crash that neither `flutter analyze`
/// nor the rest of the suite can see. This asserts the generated graph is
/// closed instead.
void main() {
  group('Injectable dependency graph', () {
    late String generated;

    setUpAll(() {
      final file = File('lib/core/di/injection.config.dart');
      expect(file.existsSync(), isTrue,
          reason:
              'Run: dart run build_runner build --delete-conflicting-outputs');
      generated = file.readAsStringSync();
    });

    // `firstTypeArg` strips the generated library prefix (e.g. `_i461.`) so a
    // type re-exported through a barrel (`core/services/x.dart` ->
    // `domain/services/x.dart`) compares equal to its canonical registration.
    // get_it resolves by runtime Type, so these are the same registration; the
    // generator merely aliases the same library under two prefixes.
    String firstTypeArg(String args) =>
        args.split(',').first.trim().replaceFirst(RegExp(r'^_[A-Za-z0-9]+\.'), '');

    test('every requested type is registered', () {
      final registered = RegExp(
              r'gh\.(?:singleton|lazySingleton|factory|singletonAsync|factoryAsync|lazySingletonAsync|factoryParam|factoryParamAsync)<([^>]+)>')
          .allMatches(generated)
          .map((m) => firstTypeArg(m.group(1)!))
          .toSet();

      // Fail loudly if injectable's output format changed and the regex above
      // silently stopped matching.
      expect(registered.length, greaterThan(20),
          reason: 'Parsed too few registrations — the regex is likely stale');

      final requested = RegExp(r'gh<([^>]+)>\(\)')
          .allMatches(generated)
          .map((m) => firstTypeArg(m.group(1)!))
          .toSet();
      expect(requested, isNotEmpty);

      final missing = requested.difference(registered);
      expect(missing, isEmpty,
          reason: 'Unregistered dependencies — configureDependencies() will '
              'throw at launch. Add an @injectable/@module provider for: $missing');
    });

    test('dart:io HttpClient is provided by NetworkModule', () {
      expect(generated, contains(r'class _$NetworkModule'));
      expect(generated, contains('HttpClient>('));
      expect(generated, contains('networkModule.httpClient'));
    });
  });
}
