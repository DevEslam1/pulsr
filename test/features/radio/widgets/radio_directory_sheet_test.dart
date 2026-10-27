// test/features/radio/widgets/radio_directory_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/radio_browser_service.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:pulsr/features/radio/presentation/widgets/radio_directory_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockRadioBrowserService extends Mock implements RadioBrowserService {}

class _MockRadioStationStore extends Mock implements RadioStationStore {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockRadioBrowserService service;
  late _MockRadioStationStore store;
  late RadioStation station;

  setUpAll(() {
    registerFallbackValue(
      RadioStation.create(name: 'fallback', url: 'https://fallback.example'),
    );
  });

  setUp(() {
    service = _MockRadioBrowserService();
    store = _MockRadioStationStore();
    station = RadioStation.create(
      name: 'Jazz FM',
      url: 'https://stream.example/jazz',
      genre: 'jazz',
    );
    when(() => store.add(any())).thenAnswer((_) async {});
    when(() => service.isReachable(any())).thenAnswer((_) async => true);
  });

  Widget host() => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RadioDirectorySheet(service: service, store: store),
        ),
      );

  testWidgets('lists directory results and adds a station', (tester) async {
    when(() => service.search(
          query: any(named: 'query'),
          country: any(named: 'country'),
          tag: any(named: 'tag'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => [station]);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Jazz FM'), findsOneWidget);
    expect(find.text('jazz'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    verify(() => store.add(station)).called(1);
    expect(find.text('Added'), findsWidgets);
  });

  testWidgets('shows a retry state when the directory fails', (tester) async {
    when(() => service.search(
          query: any(named: 'query'),
          country: any(named: 'country'),
          tag: any(named: 'tag'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => throw Exception('offline'));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load the radio directory"), findsOneWidget);
    expect(find.text('Retry'), findsWidgets);
  });

  testWidgets('shows the empty state for a query with no matches',
      (tester) async {
    when(() => service.search(
          query: any(named: 'query'),
          country: any(named: 'country'),
          tag: any(named: 'tag'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => const []);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('No stations found'), findsOneWidget);
  });

  testWidgets('refuses a station whose stream cannot be reached',
      (tester) async {
    when(() => service.search(
          query: any(named: 'query'),
          country: any(named: 'country'),
          tag: any(named: 'tag'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => [station]);
    when(() => service.isReachable(any())).thenAnswer((_) async => false);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    verifyNever(() => store.add(any()));
    expect(
      find.text("Couldn't reach this stream. Try another station."),
      findsOneWidget,
    );
  });
}
