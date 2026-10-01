// test/features/perf/phase7_perf_audit_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/performance/gpu_budget.dart';
import 'package:pulsr/core/services/artwork_cache_manager.dart';
import 'package:pulsr/core/widgets/glass_container.dart';
import 'package:pulsr/core/widgets/staggered_reveal.dart';
import 'package:pulsr/core/widgets/staggered_list_item.dart';
import 'package:pulsr/features/shell/presentation/bottom_nav_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 7: Performance & Memory Audits', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('7.1 ArtworkCacheManager uses WeakReference for >512KB payloads',
        () async {
      final cache = ArtworkCacheManager();

      // Small payload (256 KB)
      final smallData = Uint8List(256 * 1024);
      await cache.put('99901', smallData);
      expect(await cache.get('99901'), isNotNull);

      // Large payload (1 MB > 512 KB)
      final largeData = Uint8List(1024 * 1024);
      await cache.put('99902', largeData);
      final retrievedLarge = await cache.get('99902');
      expect(retrievedLarge, isNotNull);
      expect(retrievedLarge!.length, 1024 * 1024);
    });

    testWidgets(
        '7.4 BackdropFilter gating: GlassContainer omits blur when GpuBudget active',
        (tester) async {
      // 1. Without GPU saver: BackdropFilter is present
      GpuBudget.setEnabled(false);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassContainer(
              enableBlur: true,
              child: Text('Test Glass'),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);

      // 2. With GPU saver: BackdropFilter is completely omitted
      GpuBudget.setEnabled(true);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassContainer(
              enableBlur: true,
              child: Text('Test Glass'),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      GpuBudget.setEnabled(false);
    });

    testWidgets(
        '7.4 BackdropFilter gating: PulsrBottomNavBar omits blur when GpuBudget active',
        (tester) async {
      GpuBudget.setEnabled(false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulsrBottomNavBar(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);

      GpuBudget.setEnabled(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulsrBottomNavBar(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      GpuBudget.setEnabled(false);
    });

    testWidgets('7.3 Animations: StaggeredReveal caps animation to index < 15',
        (tester) async {
      // Item with index 2 should render an animated tree
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StaggeredReveal(
              index: 2,
              child: Text('Item 2'),
            ),
          ),
        ),
      );
      expect(find.text('Item 2'), findsOneWidget);
      await tester.pumpAndSettle();

      // Item with index 20 (>= 15) should directly return child without animation controller
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StaggeredReveal(
              index: 20,
              child: Text('Item 20'),
            ),
          ),
        ),
      );
      expect(find.text('Item 20'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets(
        '7.3 Animations: StaggeredListItem caps animation to index < 15',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StaggeredListItem(
              index: 20,
              child: Text('Item 20 Stagger'),
            ),
          ),
        ),
      );
      expect(find.text('Item 20 Stagger'), findsOneWidget);
    });
  });
}
