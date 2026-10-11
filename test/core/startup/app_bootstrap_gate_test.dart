// test/core/startup/app_bootstrap_gate_test.dart
//
// Verifies the root widget's dependency gate: a cold start whose async DI
// singletons are missing/pending must render a recoverable boot screen instead
// of throwing the un-ready StateError that previously black-screened startup.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/di/injection.dart' show getIt;
import 'package:pulsr/core/utils/error_logger.dart';
import 'package:pulsr/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in const [
      'com.pulsr.music/hires_dac',
      'com.pulsr.music/hires_dac_events',
      'com.pulsr.music/proxy',
      'dev.fluttercommunity.plus/connectivity_status',
      'com.pulsr.music/purity',
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(channel), (_) async => null);
    }
  });

  tearDown(() async {
    ErrorLogger.onCrashReported = null;
    await getIt.reset();
  });

  testWidgets('renders a recoverable boot/retry screen when DI is not ready',
      (tester) async {
    await tester.pumpWidget(const PulsrApp());
    await tester.pump();

    // Missing async singletons resolve to the retry variant, never a crash.
    expect(find.text('Pulsr could not finish starting up'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.byType(PulsrApp), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Pulsr could not finish starting up'), findsOneWidget);
  });
}
