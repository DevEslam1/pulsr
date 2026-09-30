import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/cloud_sync_service.dart';
import 'package:pulsr/features/settings/presentation/cloud_backup_dashboard_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockCloudSyncService extends Mock implements CloudSyncService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCloudSyncService mockSyncService;

  setUp(() {
    mockSyncService = MockCloudSyncService();
    when(() => mockSyncService.isFavoritesSyncEnabled).thenAnswer((_) async => true);
    when(() => mockSyncService.isPlaylistsSyncEnabled).thenAnswer((_) async => true);
    when(() => mockSyncService.lastSyncTime).thenReturn(null);
  });

  testWidgets('[H-21] _performSync surfaces specific exception message to user on sync failure', (tester) async {
    when(() => mockSyncService.syncAll()).thenThrow(Exception('Authentication token expired'));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CloudBackupDashboardScreen(syncService: mockSyncService),
      ),
    );

    await tester.pumpAndSettle();

    // Find and tap Sync Now button
    final syncNowBtn = find.text('Sync Now');
    expect(syncNowBtn, findsOneWidget);
    await tester.tap(syncNowBtn);
    await tester.pumpAndSettle();

    // Verify SnackBar contains the specific error details rather than generic text only
    expect(find.textContaining('Authentication token expired'), findsOneWidget);
  });

  testWidgets('[M-27] screen disables sync button and scope switches when syncService is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CloudBackupDashboardScreen(syncService: null),
      ),
    );

    await tester.pumpAndSettle();

    final filledBtn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(filledBtn.onPressed, isNull);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, isNotEmpty);
    for (final s in switches) {
      expect(s.onChanged, isNull);
    }
  });

  testWidgets('[M-27] toggling sync scopes calls service methods when syncService is present', (tester) async {
    when(() => mockSyncService.setFavoritesSyncEnabled(any())).thenAnswer((_) async {});
    when(() => mockSyncService.setPlaylistsSyncEnabled(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CloudBackupDashboardScreen(syncService: mockSyncService),
      ),
    );

    await tester.pumpAndSettle();

    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(2));

    await tester.tap(switches.first);
    await tester.pumpAndSettle();
    verify(() => mockSyncService.setFavoritesSyncEnabled(false)).called(1);

    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    verify(() => mockSyncService.setPlaylistsSyncEnabled(false)).called(1);
  });
}
