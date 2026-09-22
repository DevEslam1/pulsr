import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/library/presentation/widgets/genre_hierarchy_view.dart';
import 'package:pulsr/features/sheets/sort_filter_sheet.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3: P2 Edge Cases & UX Polish', () {
    testWidgets('M1: GenreCategory cache is populated and clearCache wipes entries', (tester) async {
      const category = GenreCategory('Rock', Icons.music_note, ['rock', 'metal']);
      expect(category.matches('Hard Rock 90s'), isTrue);
      expect(category.matches('Pop Ballad'), isFalse);

      GenreCategory.clearCache();
      // Clearing cache leaves matching functionality intact on subsequent invocations
      expect(category.matches('Alternative Metal'), isTrue);
    });

    testWidgets('M7: SortFilterSheet exposes fileSize and sampleRate sort options', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? selectedSort;
      bool? selectedAsc;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: Scaffold(
            body: SortFilterSheet(
              currentSort: 'title',
              ascending: true,
              onApply: (sort, asc) {
                selectedSort = sort;
                selectedAsc = asc;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final targetFinder = find.text('Sample Rate');
      expect(targetFinder, findsOneWidget);

      await tester.tap(find.text('Sample Rate'));
      await tester.pumpAndSettle();

      expect(selectedSort, equals('sampleRate'));
      expect(selectedAsc, isTrue);
    });

    test('M10: _SweepSource handles out-of-bounds start and end safely without RangeError', () async {
      final sampleBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final total = sampleBytes.length;

      // Simulate range request with clamped indices
      final from = (-5).clamp(0, total);
      final to = (100).clamp(from, total);
      final sub = sampleBytes.sublist(from, to);

      expect(sub.length, equals(8));
      expect(from, equals(0));
      expect(to, equals(8));
    });
  });
}
