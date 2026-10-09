// Covers lib/features/settings/presentation/widgets/storage_cache_section.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/artwork_cache_manager.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/settings/presentation/widgets/storage_cache_section.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('pulsr_storage_test');
    File('${tempDir.path}${Platform.pathSeparator}song.lrc')
        .writeAsStringSync('lyric line');
    File('${tempDir.path}${Platform.pathSeparator}scratch.bin')
        .writeAsStringSync('temporary data');
    File('${tempDir.path}${Platform.pathSeparator}artwork_thumb.bin')
        .writeAsStringSync('artwork');
    File('${tempDir.path}${Platform.pathSeparator}ytm_stream.bin')
        .writeAsStringSync('stream');

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );

    await ArtworkCacheManager().setMaxCacheSizeMb(100);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: StorageCacheSection()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('renders the storage breakdown and cache rows', (tester) async {
    await pumpSection(tester);

    expect(find.text(l10n.storageBreakdown), findsOneWidget);
    expect(find.text(l10n.artworkCache), findsOneWidget);
    expect(find.text(l10n.maximumArtworkCacheLimit), findsOneWidget);
    expect(
        find.text(l10n.maxMbAutoEvicts(
            ArtworkCacheManager().maxCacheSizeMb)),
        findsOneWidget);
    // YTM is compile-time disabled so the stream cache row is absent.
    expect(find.text(l10n.youtubeStreamDiskCache), findsNothing);
    // Lyrics + temp legend rows are always shown.
    expect(find.textContaining('Lyrics'), findsWidgets);
  });

  testWidgets('maximum cache picker changes the manager limit',
      (tester) async {
    // The bottom-sheet container draws a colored DecoratedBox directly around
    // the picker's ListTiles, which trips a debug-only framework assertion.
    // Ignore that specific framework diagnostic; the interaction is real.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('ListTile background color')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    await pumpSection(tester);

    await tester.tap(find.text(l10n.maximumArtworkCacheLimit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.maximumArtworkCacheLimit), findsWidgets);
    await tester.tap(find.text(l10n.mbValue(250)).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(ArtworkCacheManager().maxCacheSizeMb, 250);
  });

  testWidgets('clearing artwork cache can be cancelled', (tester) async {
    await pumpSection(tester);

    await tester.tap(find.widgetWithText(TextButton, l10n.clear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Confirmation dialog is shown.
    expect(find.text(l10n.confirm), findsOneWidget);
    await tester.tap(find.text(l10n.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.artworkCacheCleared), findsNothing);
  });

  testWidgets('confirming artwork cache clear shows a success toast',
      (tester) async {
    await pumpSection(tester);

    await tester.tap(find.widgetWithText(TextButton, l10n.clear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(FilledButton, l10n.clear));
    await tester.pump();
    // Advance the dialog's pop animation so the confirmation future resolves
    // and the clear handler starts.
    await tester.pump(const Duration(milliseconds: 400));
    // The clear + refresh path touches the real filesystem. Interleave the
    // fake-async pump with real event-loop turns so the awaited IO completes.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }

    expect(find.text(l10n.artworkCacheCleared), findsOneWidget);

    // Drain the toast auto-dismiss timer.
    await tester.pump(const Duration(seconds: 3));
  });
}
