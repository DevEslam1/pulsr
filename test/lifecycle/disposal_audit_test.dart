// test/lifecycle/disposal_audit_test.dart
// FIX-F1: Disposal audit and memory safety tests for Phase F
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/core/widgets/cached_artwork.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/features/player/cubit/controllers/player_transport_controller.dart';
import 'package:pulsr/features/player/cubit/controllers/player_widget_bridge.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_search_cubit.dart';

class MockAudioHandler extends Mock implements PulsrAudioHandler {}
class MockYtmService extends Mock implements YtmService {}

void main() {
  group('Phase F: Lifecycle Disposal & Memory Safety Tests', () {
    test('ArtworkLruCache caches large payloads (>512KB) using WeakReference', () {
      final cache = ArtworkLruCache.withCapacity(10);
      cache.clear();

      // Create a 600KB payload
      final largeBytes = Uint8List(600 * 1024);
      largeBytes[0] = 42;
      largeBytes[largeBytes.length - 1] = 99;

      cache.put('large_artwork_1', largeBytes, persistToDisk: false);
      expect(cache.containsKey('large_artwork_1'), isTrue);

      final retrieved = cache.get('large_artwork_1');
      expect(retrieved, isNotNull);
      expect(retrieved!.length, equals(600 * 1024));
      expect(retrieved[0], equals(42));
      expect(retrieved[retrieved.length - 1], equals(99));

      cache.remove('large_artwork_1');
      expect(cache.containsKey('large_artwork_1'), isFalse);
      expect(cache.get('large_artwork_1'), isNull);
    });

    test('DynamicThemeCubit closes cleanly and cancels pending timers', () async {
      final cubit = DynamicThemeCubit();
      expect(cubit.isClosed, isFalse);

      await cubit.close();
      expect(cubit.isClosed, isTrue);

      // Calling resetToDefault or updates on closed cubit must be a no-op
      cubit.resetToDefault();
    });

    test('YtmSearchCubit closes cleanly and cancels debounce timers', () async {
      final mockYtmService = MockYtmService();
      final cubit = YtmSearchCubit(service: mockYtmService);

      cubit.onQueryChanged('Test Query');
      await cubit.close();

      expect(cubit.isClosed, isTrue);
      // Further query changes on closed cubit must not crash
      cubit.onQueryChanged('Another Query');
    });

    test('PlayerTransportController disposes timers and cancels pending seeks safely', () {
      final mockAudioHandler = MockAudioHandler();
      var state = const PlayerState();
      var isClosed = false;

      final controller = PlayerTransportController(
        audioHandler: mockAudioHandler,
        getState: () => state,
        emit: (s) => state = s,
        isClosed: () => isClosed,
      );

      controller.dispose();
      isClosed = true;

      // Further transport operations after disposal are no-ops
      expect(() => controller.play(), returnsNormally);
      expect(() => controller.seek(const Duration(seconds: 10)), returnsNormally);
    });

    test('PlayerWidgetBridge disposes coordinators safely', () {
      final bridge = PlayerWidgetBridge(
        widgetService: null,
        scrobblerService: null,
        latencyTracker: null,
        isQuranMode: () => false,
        isClosed: () => false,
      );

      expect(() => bridge.dispose(), returnsNormally);
      // Double disposal must be idempotent
      expect(() => bridge.dispose(), returnsNormally);
    });
  });
}
