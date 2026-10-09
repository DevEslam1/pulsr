// test/firebase_options_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/firebase_options.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('DefaultFirebaseOptions constants', () {
    test('every platform constant targets the same Firebase project', () {
      const options = [
        DefaultFirebaseOptions.web,
        DefaultFirebaseOptions.android,
        DefaultFirebaseOptions.ios,
        DefaultFirebaseOptions.macos,
        DefaultFirebaseOptions.windows,
      ];
      for (final o in options) {
        expect(o.projectId, 'pulsr-24243');
      }
      expect(DefaultFirebaseOptions.android.apiKey, isNotEmpty);
      expect(DefaultFirebaseOptions.ios.iosClientId, isNotEmpty);
      expect(DefaultFirebaseOptions.ios.iosBundleId, 'com.pulsr.music');
    });
  });

  group('DefaultFirebaseOptions.currentPlatform', () {
    test('resolves each supported target platform', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(DefaultFirebaseOptions.currentPlatform,
          same(DefaultFirebaseOptions.android));

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(DefaultFirebaseOptions.currentPlatform,
          same(DefaultFirebaseOptions.ios));

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(DefaultFirebaseOptions.currentPlatform,
          same(DefaultFirebaseOptions.macos));

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(DefaultFirebaseOptions.currentPlatform,
          same(DefaultFirebaseOptions.windows));
    });

    test('throws for unsupported platforms', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(
        () => DefaultFirebaseOptions.currentPlatform,
        throwsA(isA<UnsupportedError>()),
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      expect(
        () => DefaultFirebaseOptions.currentPlatform,
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
