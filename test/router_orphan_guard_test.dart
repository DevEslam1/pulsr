import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against orphan GoRouter routes (defined but unreachable from any
/// UI navigation call) and dead parameterized pushes (`/album/123`,
/// `/genre/x`) that fall through to the Page-Not-Found builder.
///
/// Scans the real sources under `lib/`, so adding a route without wiring an
/// entry point fails this test.
void main() {
  group('Router wiring guard', () {
    late Directory packageRoot;
    late String routerSource;
    late Map<String, String> libSources;

    setUpAll(() {
      packageRoot = _findPackageRoot();
      routerSource =
          File('${packageRoot.path}/lib/core/router/app_router.dart')
              .readAsStringSync();
      libSources = {};
      for (final entity in Directory('${packageRoot.path}/lib')
          .listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          libSources[entity.path] = entity.readAsStringSync();
        }
      }
    });

    Set<String> routePaths() {
      // Matches: path: '/queue', — including the conditional YTM block.
      final exp = RegExp(r"""path:\s*'([^']+)'""");
      return exp
          .allMatches(routerSource)
          .map((m) => m.group(1)!)
          .toSet();
    }

    Set<String> navigationTargets() {
      // Matches context.push('/x'), context.go('/y'), .push('/z'), .go('/w').
      final exp = RegExp(r"""(?:\.push|\.go)\(\s*'([^'?]+)""");
      final targets = <String>{};
      for (final source in libSources.values) {
        for (final m in exp.allMatches(source)) {
          targets.add(m.group(1)!);
        }
      }
      return targets;
    }

    test('every route is reachable from UI navigation', () {
      final routes = routePaths();
      final targets = navigationTargets();

      // Tab branches are driven by the StatefulShell, not push/go; the
      // splash screen is the router initialLocation.
      const shellDriven = {
        '/splash',
        '/',
        '/library',
        '/search',
        '/playlists',
        '/settings',
      };

      final orphans =
          routes.difference(targets).difference(shellDriven).toList()..sort();
      expect(
        orphans,
        isEmpty,
        reason:
            'Orphan routes with no push/go call-site: $orphans. '
            'Wire an entry point (button/tile/chip) or delete the route.',
      );
    });

    test('no parameterized pushes to flat extra-based routes', () {
      // These routes accept data via `extra:` only; pushing a sub-path
      // (e.g. /album/5) always lands on Page Not Found.
      final exp = RegExp(
        r"""\.push\(\s*'((?:/album|/artist|/genre|/year|/playlist|/folder|/tag-editor)/[^']*)'""",
      );
      final offenders = <String>[];
      for (final entry in libSources.entries) {
        for (final m in exp.allMatches(entry.value)) {
          final target = m.group(1)!;
          // '/playlist/manage' is a legitimate nested route.
          if (target == '/playlist/manage') continue;
          offenders.add('${entry.key} -> $target');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Dead parameterized pushes (always 404): $offenders. '
            'Push the flat path with extra: instead.',
      );
    });
  });
}

/// Walks up from this test file to the directory holding pubspec.yaml.
Directory _findPackageRoot() {
  var dir = Directory.fromUri(Platform.script.resolve('.'));
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate package root from ${dir.path}');
    }
    dir = parent;
  }
}
