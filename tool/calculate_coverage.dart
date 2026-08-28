import 'dart:io';

void main() {
  final file = File('coverage/lcov.info');
  if (!file.existsSync()) {
    print('coverage/lcov.info not found');
    return;
  }
  final lines = file.readAsLinesSync();
  String currentFile = '';
  int blocTotal = 0, blocHit = 0;
  int cubitTotal = 0, cubitHit = 0;
  final Map<String, List<int>> fileStats = {};

  for (final l in lines) {
    if (l.startsWith('SF:')) {
      currentFile = l.substring(3).replaceAll('\\', '/');
    } else if (l.startsWith('DA:')) {
      final parts = l.substring(3).split(',');
      final hits = int.parse(parts[1]);
      final isBloc = currentFile.contains('core/bloc/');
      final isCubit = currentFile.contains('features/') &&
          currentFile.contains('/cubit/') &&
          !currentFile.endsWith('_state.dart') &&
          !currentFile.endsWith('.freezed.dart');

      if (isBloc) {
        blocTotal++;
        if (hits > 0) blocHit++;
        fileStats.putIfAbsent(currentFile, () => [0, 0]);
        fileStats[currentFile]![0]++;
        if (hits > 0) fileStats[currentFile]![1]++;
      }
      if (isCubit) {
        cubitTotal++;
        if (hits > 0) cubitHit++;
        fileStats.putIfAbsent(currentFile, () => [0, 0]);
        fileStats[currentFile]![0]++;
        if (hits > 0) fileStats[currentFile]![1]++;
      }
    }
  }

  print('=== COVERAGE REPORT ===');
  fileStats.forEach((f, stats) {
    final pct = (stats[1] / stats[0] * 100).toStringAsFixed(1);
    print('$f: $pct% (${stats[1]}/${stats[0]} lines)');
  });

  final unhitDownloads = <int>[];
  bool inTarget = false;
  for (final l in lines) {
    if (l.startsWith('SF:')) {
      inTarget = l.contains('downloads_cubit.dart');
    } else if (inTarget && l.startsWith('DA:')) {
      final parts = l.substring(3).split(',');
      final lineNum = int.parse(parts[0]);
      final hits = int.parse(parts[1]);
      if (hits == 0) unhitDownloads.add(lineNum);
    }
  }
  print('Unhit lines in downloads_cubit.dart: $unhitDownloads');
  final blocPct = blocTotal > 0 ? (blocHit / blocTotal * 100).toStringAsFixed(1) : '0.0';
  final cubitPct = cubitTotal > 0 ? (cubitHit / cubitTotal * 100).toStringAsFixed(1) : '0.0';
  final overallTotal = blocTotal + cubitTotal;
  final overallHit = blocHit + cubitHit;
  final overallPct = overallTotal > 0 ? (overallHit / overallTotal * 100).toStringAsFixed(1) : '0.0';
  print('---');
  print('lib/core/bloc/**: $blocPct% ($blocHit/$blocTotal lines)');
  print('lib/features/**/cubit/**: $cubitPct% ($cubitHit/$cubitTotal lines)');
  print('Combined Target Coverage: $overallPct% ($overallHit/$overallTotal lines)');
}
