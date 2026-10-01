// test/features/downloads/storage_stats_header_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/features/downloads/presentation/widgets/storage_stats_header.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  group('StorageStatsHeader Tests', () {
    const stats = StorageStats(
      usedBytes: 1024 * 1024 * 500, // 500 MB
      freeBytes: 1024 * 1024 * 1500, // 1.5 GB
      totalBytes: 1024 * 1024 * 2000, // 2 GB (25% used)
      downloadedSongsCount: 50,
    );

    test('StorageStats calculates percentage correctly', () {
      expect(stats.usedPercentage, equals(0.25));
    });

    testWidgets('renders used and free storage readouts accurately',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: StorageStatsHeader(stats: stats),
          ),
        ),
      );

      expect(find.byType(StorageStatsHeader), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, equals(0.25));
    });

    testWidgets('renders properly under RTL directionality', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StorageStatsHeader(stats: stats),
            ),
          ),
        ),
      );

      expect(find.byType(StorageStatsHeader), findsOneWidget);
    });
  });
}
