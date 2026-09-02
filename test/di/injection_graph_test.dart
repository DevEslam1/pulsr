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

    String firstTypeArg(String args) => args.split(',').first.trim();

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

    test('exactly ONE binding per registered type/interface', () {
      final registrations = RegExp(
              r'gh\.(?:singleton|lazySingleton|factory|singletonAsync|factoryAsync|lazySingletonAsync|factoryParam|factoryParamAsync)<([^>]+)>')
          .allMatches(generated)
          .map((m) => firstTypeArg(m.group(1)!))
          .toList();

      final counts = <String, int>{};
      for (final type in registrations) {
        counts[type] = (counts[type] ?? 0) + 1;
      }

      final duplicates = counts.entries.where((e) => e.value > 1).map((e) => '${e.key} (${e.value} bindings)').toList();
      expect(duplicates, isEmpty,
          reason: 'Duplicate bindings found in injection graph: $duplicates');
    });
  });

  group('Clean Architecture Layer Boundaries', () {
    test('domain layer has zero imports of features layer', () {
      final domainDir = Directory('lib/domain');
      if (!domainDir.existsSync()) return;

      final domainFiles = domainDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.contains('.freezed.') && !f.path.contains('.g.'));

      for (final file in domainFiles) {
        final content = file.readAsStringSync();
        final importLines = content
            .split('\n')
            .where((l) => l.trim().startsWith('import '))
            .toList();

        for (final line in importLines) {
          expect(line.contains('features/'), isFalse,
              reason: 'Domain violation in ${file.path}: imports features layer ($line)');
        }
      }
    });

    test('data layer has zero imports of features layer', () {
      final dataDir = Directory('lib/data');
      if (!dataDir.existsSync()) return;

      final dataFiles = dataDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.contains('.freezed.') && !f.path.contains('.g.'));

      for (final file in dataFiles) {
        final content = file.readAsStringSync();
        final importLines = content
            .split('\n')
            .where((l) => l.trim().startsWith('import '))
            .toList();

        for (final line in importLines) {
          expect(line.contains('features/'), isFalse,
              reason: 'Data layer violation in ${file.path}: imports presentation/feature ($line)');
        }
      }
    });

    test('core layer services have zero imports of features layer', () {
      final coreServicesDir = Directory('lib/core/services');
      if (!coreServicesDir.existsSync()) return;

      final coreFiles = coreServicesDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') &&
              !f.path.contains('file_intent_handler.dart') &&
              !f.path.contains('.freezed.') &&
              !f.path.contains('.g.'));

      for (final file in coreFiles) {
        final content = file.readAsStringSync();
        final importLines = content
            .split('\n')
            .where((l) => l.trim().startsWith('import '))
            .toList();

        for (final line in importLines) {
          expect(line.contains('features/'), isFalse,
              reason: 'Core layer violation in ${file.path}: imports presentation/feature ($line)');
        }
      }
    });

    test('YtDownloadService must live in data/downloads (A5/N-01)', () {
      expect(File('lib/core/services/yt_download_service.dart').existsSync(), isFalse,
          reason: 'YtDownloadService duplicate/legacy file in core/services must be removed (N-01)');
      expect(File('lib/data/downloads/yt_download_service.dart').existsSync(), isTrue,
          reason: 'YtDownloadService canonical location is lib/data/downloads/yt_download_service.dart');
    });

    test('no duplicate classes or stale twins across lib/', () {
      // Check stale twin files
      final staleFiles = [
        'lib/features/tag_editor/tag_editor_cubit.dart',
        'lib/features/tag_editor/tag_editor_screen.dart',
        'lib/features/tag_editor/tag_editor_state.dart',
        'lib/features/smart_playlist_builder/smart_playlist_builder_cubit.dart',
        'lib/features/smart_playlist_builder/smart_playlist_builder_screen.dart',
        'lib/features/smart_playlist_builder/smart_playlist_builder_state.dart',
        'lib/features/widgets/widget_service.dart',
        'lib/features/ytm_search/cubit/ytm_download_cubit.dart',
        'lib/features/ytm_search/presentation/widgets/ytm_download_button.dart',
      ];

      for (final sf in staleFiles) {
        expect(File(sf).existsSync(), isFalse,
            reason: 'Stale duplicate file must be removed: $sf');
      }

      // Check no duplicate class declarations in lib/ (excluding generated files)
      final classRegex = RegExp(r'^\s*class\s+([A-Za-z0-9_]+)', multiLine: true);
      final classMap = <String, List<String>>{};

      final libFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') &&
              !f.path.contains('.g.') &&
              !f.path.contains('.freezed.') &&
              !f.path.contains('.config.'));

      for (final file in libFiles) {
        final content = file.readAsStringSync();
        for (final match in classRegex.allMatches(content)) {
          final className = match.group(1)!;
          if (className.startsWith('_')) continue; // Skip private classes
          classMap.putIfAbsent(className, () => []).add(file.path);
        }
      }

      final duplicateClasses = classMap.entries
          .where((e) => e.value.length > 1)
          .map((e) => '${e.key} defined in: ${e.value}')
          .toList();

      expect(duplicateClasses, isEmpty,
          reason: 'Duplicate class names detected across lib/: $duplicateClasses');
    });
  });
}
