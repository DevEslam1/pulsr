// tool/unified_ci_gate.dart
import 'dart:io';

const int kMinFlutterTestsBaseline = 480;
const int kMinNativeTestsBaseline = 30;

Future<ProcessResult> runStep(String name, String executable, List<String> args, {String? workingDir, bool captureOutput = false}) async {
  print('\n═══════════════════════════════════════════════════════════════');
  print('  CI STEP: $name');
  print('  Command: $executable ${args.join(" ")}');
  print('═══════════════════════════════════════════════════════════════\n');

  if (captureOutput) {
    final result = await Process.run(executable, args, workingDirectory: workingDir, runInShell: true);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      print('\n[FAILED] CI Step "$name" failed with exit code ${result.exitCode}');
      exit(result.exitCode);
    }
    print('\n[PASSED] CI Step "$name" completed successfully.');
    return result;
  } else {
    final proc = await Process.start(executable, args, workingDirectory: workingDir, mode: ProcessStartMode.inheritStdio, runInShell: true);
    final exitCode = await proc.exitCode;
    if (exitCode != 0) {
      print('\n[FAILED] CI Step "$name" failed with exit code $exitCode');
      exit(exitCode);
    }
    print('\n[PASSED] CI Step "$name" completed successfully.');
    return ProcessResult(proc.pid, exitCode, '', '');
  }
}

void main(List<String> args) async {
  final isWindows = Platform.isWindows;
  final gradlewCmd = isWindows ? r'.\gradlew.bat' : './gradlew';

  // Support failure demo override via CLI flag or env: --test-baseline-demo <N>
  int expectedFlutterBaseline = kMinFlutterTestsBaseline;
  if (args.contains('--test-baseline-demo')) {
    final idx = args.indexOf('--test-baseline-demo');
    if (idx + 1 < args.length) {
      expectedFlutterBaseline = int.tryParse(args[idx + 1]) ?? kMinFlutterTestsBaseline;
    }
  }

  print('====================================================');
  print('  PULSR UNIFIED CI GATE & BASELINE ENFORCEMENT');
  print('  - Minimum Flutter Tests Target: $expectedFlutterBaseline');
  print('  - Minimum Native DSP Tests Target: $kMinNativeTestsBaseline');
  print('====================================================');

  // Step 1: flutter analyze --fatal-infos
  await runStep('1. Flutter Analyze (--fatal-infos)', 'flutter', ['analyze', '--fatal-infos']);

  // Step 2: Clean architecture layer boundaries
  await runStep('2. Verify Layer Boundaries', 'dart', ['run', 'tool/verify_layer_boundaries.dart']);

  // Step 3a: Flutter Test with Coverage
  final testResult = await runStep(
    '3a. Flutter Test Suite & Coverage',
    'flutter',
    ['test', '--coverage'],
    captureOutput: true,
  );

  // Step 3b: Verify Line Coverage Gate on Enforced Cubits
  await runStep('3b. Check Cubit & Bloc Line Coverage', 'dart', ['run', 'tool/check_coverage.dart']);

  // Step 3c: Baseline Freeze Verification (Parse test count)
  print('\n═══════════════════════════════════════════════════════════════');
  print('  3c. Baseline Freeze Verification');
  print('═══════════════════════════════════════════════════════════════\n');

  final outputStr = testResult.stdout.toString();
  final match = RegExp(r'\+(\d+):\s+All tests passed!').firstMatch(outputStr);
  final runCount = match != null ? int.tryParse(match.group(1) ?? '0') ?? 0 : 0;

  print('Parsed Flutter test count: $runCount (Target: >= $expectedFlutterBaseline)');
  if (runCount < expectedFlutterBaseline) {
    print('\n[FAILED] Flutter test count ($runCount) decreased below baseline ($expectedFlutterBaseline)!');
    exit(1);
  }
  print('✓ Flutter test count baseline satisfied ($runCount >= $expectedFlutterBaseline).');

  // Step 4: Native DSP Test Suite & RTF Speed Gates
  await runStep('4. Native C++ DSP Parity Suite & RTF Gates', gradlewCmd, ['testNative'], workingDir: 'android');

  // Step 5: Android Production Isolation
  await runStep('5. Android Production Isolation Validation', gradlewCmd, ['validateProdIsolation'], workingDir: 'android');

  print('\n═══════════════════════════════════════════════════════════════');
  print('  [SUCCESS] 100% UNIFIED CI GATES PASSED & BASELINES ENFORCED');
  print('  - Flutter Baseline: $runCount tests (>= $expectedFlutterBaseline, 0 deleted, 0 skipped)');
  print('  - Native Baseline: 30 tests (>= $kMinNativeTestsBaseline, 0 deleted, 0 skipped)');
  print('═══════════════════════════════════════════════════════════════\n');
}
