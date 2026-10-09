// EmptyLibrary coverage: the three visual states (needs permission, scanning
// with progress, empty library), the permission-request dialog branches, the
// scan-progress subscription, and the hidden-folders navigation. The primary
// home suite only asserts that EmptyLibrary is present, not its behaviour.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/home/presentation/widgets/empty_library.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockScanner extends Mock implements MediaScannerService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupAppLocalizations(const Locale('en'));

  late _MockScanner scanner;
  late StreamController<double> progress;

  setUp(() async {
    await getIt.reset();
    scanner = _MockScanner();
    progress = StreamController<double>.broadcast();
    when(() => scanner.checkPermission()).thenAnswer((_) async => true);
    when(() => scanner.requestPermission()).thenAnswer((_) async => true);
    when(() => scanner.scanDeviceLibrary()).thenAnswer((_) async => 3);
    when(() => scanner.scanProgress).thenAnswer((_) => progress.stream);
  });

  tearDown(() async {
    await progress.close();
    await getIt.reset();
  });

  Widget wrap({bool provideScanner = true}) {
    final router = GoRouter(
      initialLocation: '/target',
      routes: [
        GoRoute(
          path: '/target',
          builder: (_, __) {
            final child = const EmptyLibrary();
            if (!provideScanner) {
              return Scaffold(body: child);
            }
            return RepositoryProvider<MediaScannerService>.value(
              value: scanner,
              child: Scaffold(body: child),
            );
          },
        ),
        GoRoute(
          path: '/hidden-folders',
          builder: (_, __) =>
              const Scaffold(body: Text('hidden-folders-route')),
        ),
      ],
    );

    return MaterialApp.router(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }

  testWidgets('shows the empty library prompt and scans on demand',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text(l10n.noMusicYet), findsOneWidget);

    await tester.tap(find.text(l10n.scanStorage));
    await tester.pumpAndSettle();

    verify(() => scanner.scanDeviceLibrary()).called(1);
    expect(find.text(l10n.scanComplete(3)), findsOneWidget);
  });

  testWidgets('shows the permission state when access is denied',
      (tester) async {
    when(() => scanner.checkPermission()).thenAnswer((_) async => false);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text(l10n.homePermissionNeeded), findsOneWidget);
    expect(find.text(l10n.homeGrantPermission), findsOneWidget);
  });

  testWidgets('cancelling the permission dialog does not request access',
      (tester) async {
    when(() => scanner.checkPermission()).thenAnswer((_) async => false);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.homeGrantPermission));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    verifyNever(() => scanner.requestPermission());
    expect(find.text(l10n.homePermissionNeeded), findsOneWidget);
  });

  testWidgets('confirming the permission dialog grants and then scans',
      (tester) async {
    when(() => scanner.checkPermission()).thenAnswer((_) async => false);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.homeGrantPermission));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeGrantPermission).last);
    await tester.pumpAndSettle();

    verify(() => scanner.requestPermission()).called(1);
    verify(() => scanner.scanDeviceLibrary()).called(1);
  });

  testWidgets('a denied request keeps the permission state', (tester) async {
    when(() => scanner.checkPermission()).thenAnswer((_) async => false);
    when(() => scanner.requestPermission()).thenAnswer((_) async => false);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.homeGrantPermission));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.homeGrantPermission).last);
    await tester.pumpAndSettle();

    verify(() => scanner.requestPermission()).called(1);
    verifyNever(() => scanner.scanDeviceLibrary());
    expect(find.text(l10n.homePermissionNeeded), findsOneWidget);
  });

  testWidgets('renders a determinate progress bar while scanning',
      (tester) async {
    final completer = Completer<int>();
    when(() => scanner.scanDeviceLibrary()).thenAnswer((_) => completer.future);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.scanStorage));
    await tester.pump();

    expect(find.text(l10n.scanningStorage), findsOneWidget);
    // The determinate bar only appears once progress is reported.
    expect(find.byType(LinearProgressIndicator), findsNothing);

    progress.add(0.42);
    await tester.pump();

    final bar =
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.42, 0.001));
    expect(find.text(l10n.homeScanProgress(42)), findsOneWidget);

    completer.complete(1);
    await tester.pumpAndSettle();
  });

  testWidgets('falls back to getIt when no scanner provider is present',
      (tester) async {
    getIt.registerSingleton<MediaScannerService>(scanner);

    await tester.pumpWidget(wrap(provideScanner: false));
    await tester.pumpAndSettle();

    expect(find.text(l10n.noMusicYet), findsOneWidget);
    await tester.tap(find.text(l10n.scanStorage));
    await tester.pumpAndSettle();
    verify(() => scanner.scanDeviceLibrary()).called(1);
  });

  testWidgets('the hidden-folders action navigates', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.hiddenFolders));
    await tester.pumpAndSettle();

    expect(find.text('hidden-folders-route'), findsOneWidget);
  });
}
