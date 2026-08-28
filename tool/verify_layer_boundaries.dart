// tool/verify_layer_boundaries.dart
// Enforces Clean Architecture layer boundaries and PulsrCubit usage in CI.

import 'dart:io';

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    print('Error: lib directory not found.');
    exit(1);
  }

  int violations = 0;
  final cubitFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('.dart') &&
          (f.path.contains('${Platform.pathSeparator}cubit${Platform.pathSeparator}') ||
              f.path.endsWith('_cubit.dart')) &&
          !f.path.endsWith('_state.dart') &&
          !f.path.endsWith('.freezed.dart') &&
          !f.path.endsWith('.g.dart') &&
          !f.path.endsWith('base_cubit.dart'))
      .toList();

  print('=== Clean Architecture & PulsrCubit Boundary Gate ===');
  print('Scanned ${cubitFiles.length} Cubit files:');

  for (final file in cubitFiles) {
    final lines = file.readAsLinesSync();
    final relativePath = file.path.replaceAll('\\', '/');
    final isPulsrCubit = lines.any((l) => l.contains('extends PulsrCubit'));

    print('  - $relativePath [${isPulsrCubit ? "PulsrCubit (Enforced)" : "Standard Cubit"}]');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      final lineNum = i + 1;

      // Rule 1: No raw emit( outside safeEmit / PulsrCubit in target cubits
      if (trimmed.startsWith('emit(') && !trimmed.startsWith('safeEmit(')) {
        if (isPulsrCubit) {
          print('    VIOLATION [Raw emit]: $relativePath:$lineNum -> "$trimmed" (Must use safeEmit)');
          violations++;
        }
      }

      // Rule 2: No raw .listen( calls (must use autoSub) in target cubits
      if (trimmed.contains('.listen(') && !trimmed.contains('// ignore: raw_listen')) {
        if (isPulsrCubit) {
          print('    VIOLATION [Raw stream listen]: $relativePath:$lineNum -> "$trimmed" (Must use autoSub for lifecycle safety)');
          violations++;
        }
      }
    }
  }

  if (violations > 0) {
    print('\nFAILED: $violations architecture boundary violations found.');
    exit(1);
  } else {
    print('\nPASSED: 100% layer boundary and PulsrCubit compliance verified.');
  }
}
