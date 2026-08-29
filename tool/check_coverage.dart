// tool/check_coverage.dart
import 'dart:io';

void main() {
  final lcovFile = File('coverage/lcov.info');
  if (!lcovFile.existsSync()) {
    print('Error: coverage/lcov.info not found');
    exit(1);
  }

  final lines = lcovFile.readAsLinesSync();
  final fileCoverage = <String, Map<String, int>>{};
  String? currentFile;

  for (final line in lines) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3).trim().replaceAll('\\', '/');
      fileCoverage[currentFile] = {'found': 0, 'hit': 0};
    } else if (line.startsWith('LF:') && currentFile != null) {
      fileCoverage[currentFile]!['found'] = int.parse(line.substring(3).trim());
    } else if (line.startsWith('LH:') && currentFile != null) {
      fileCoverage[currentFile]!['hit'] = int.parse(line.substring(3).trim());
    }
  }

  print('=== Cubit & Bloc Line Coverage Report ===');
  print('File | Lines Found | Lines Hit | Coverage % | Status');
  print('-----+-------------+-----------+------------+-------');

  // Enforced targets and their respective minimum coverage thresholds
  final enforcedThresholds = <String, double>{
    'lib/core/bloc/app_bloc_observer.dart': 90.0,
    'lib/core/bloc/base_cubit.dart': 90.0,
    'lib/features/downloads/cubit/downloads_cubit.dart': 90.0,
    'lib/features/search/cubit/search_cubit.dart': 90.0,
    'lib/features/player/cubit/player_cubit.dart': 75.0,
  };

  final cubitFiles = fileCoverage.keys.where((f) =>
      (f.contains('/cubit/') || f.contains('/bloc/')) &&
      !f.endsWith('.freezed.dart') &&
      !f.endsWith('.g.dart')
  ).toList()..sort();

  int failedEnforced = 0;

  for (final f in cubitFiles) {
    final stats = fileCoverage[f]!;
    final found = stats['found']!;
    final hit = stats['hit']!;
    final pct = found == 0 ? 100.0 : (hit / found) * 100.0;
    final isEnforced = enforcedThresholds.containsKey(f);
    final minPct = enforcedThresholds[f] ?? 0.0;
    final passed = !isEnforced || pct >= minPct;
    final status = isEnforced ? (passed ? 'PASS (>=${minPct.toInt()}%)' : 'FAIL (<${minPct.toInt()}%)') : 'Tracked';

    if (isEnforced && !passed) {
      failedEnforced++;
    }
    print('$f | $found | $hit | ${pct.toStringAsFixed(1)}% | $status');
  }

  if (failedEnforced > 0) {
    print('\n[FAILED] $failedEnforced enforced files failed coverage gates.');
    exit(1);
  } else {
    print('\n[PASSED] All enforced Cubit/Bloc coverage gates passed.');
  }
}
