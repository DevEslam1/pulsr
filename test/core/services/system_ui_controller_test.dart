// test/core/services/system_ui_controller_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/system_ui_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> systemUiCalls = [];

  setUp(() {
    systemUiCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIOverlays' ||
          call.method == 'SystemChrome.setEnabledSystemUIMode' ||
          call.method == 'SystemChrome.setSystemUIOverlayStyle') {
        systemUiCalls.add(call);
      }
      return null;
    });
    SystemUiController.instance.resetForTesting();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    SystemUiController.instance.resetForTesting();
  });

  group('SystemUiController Authority', () {
    test('open player in landscape -> close -> status bar stays hidden (immersiveSticky persists)', () {
      // 1. App starts in landscape
      SystemUiController.instance.syncMode(owner: 'app_shell', immersive: true);
      expect(SystemUiController.instance.isImmersive, isTrue);

      // 2. Open Now Playing in landscape
      SystemUiController.instance.syncMode(owner: 'now_playing', immersive: true);
      expect(SystemUiController.instance.isImmersive, isTrue);

      // 3. Close Now Playing (pop)
      SystemUiController.instance.releaseImmersive('now_playing');

      // 4. Status bar must stay hidden because app_shell is still in landscape!
      expect(SystemUiController.instance.isImmersive, isTrue,
          reason: 'AppShell is in landscape, so status bar must remain hidden after closing player');

      // 5. App rotates to portrait
      SystemUiController.instance.syncMode(owner: 'app_shell', immersive: false);
      expect(SystemUiController.instance.isImmersive, isFalse);
    });

    test('multiple requesters keep immersive mode active until all release', () {
      SystemUiController.instance.requestImmersive('screen_a');
      SystemUiController.instance.requestImmersive('screen_b');
      expect(SystemUiController.instance.isImmersive, isTrue);

      SystemUiController.instance.releaseImmersive('screen_a');
      expect(SystemUiController.instance.isImmersive, isTrue);

      SystemUiController.instance.releaseImmersive('screen_b');
      expect(SystemUiController.instance.isImmersive, isFalse);
    });

    test('invalidate forces re-application of system UI mode', () {
      SystemUiController.instance.syncMode(owner: 'app_shell', immersive: true);
      final countBefore = systemUiCalls.length;

      SystemUiController.instance.invalidate();
      expect(systemUiCalls.length, greaterThan(countBefore));
      expect(SystemUiController.instance.isImmersive, isTrue);
    });
  });
}
