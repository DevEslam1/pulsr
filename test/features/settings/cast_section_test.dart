// Covers lib/features/settings/presentation/widgets/cast_section.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/cast_section.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  final calls = <String>[];
  bool sessionAvailable = false;
  bool mdnsSupported = true;

  late MockPlayerCubit player;

  setUp(() {
    calls.clear();
    sessionAvailable = false;
    mdnsSupported = true;

    player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream).thenAnswer((_) => const Stream<PlayerState>.empty());

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.castSession),
      (call) async {
        calls.add('session:${call.method}');
        switch (call.method) {
          case 'isAvailable':
            return sessionAvailable;
          case 'castLocalFile':
            return <String, dynamic>{'success': true};
          case 'connect':
          case 'disconnect':
          case 'startDiscovery':
          case 'stopDiscovery':
            return true;
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.cast),
      (call) async {
        calls.add('mdns:${call.method}');
        switch (call.method) {
          case 'isSupported':
            return mdnsSupported;
          case 'startDiscovery':
          case 'stopDiscovery':
            return true;
          case 'castTo':
            return <String, dynamic>{'success': true};
        }
        return null;
      },
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.castSession), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.cast), null);
  });

  Future<void> pumpCast(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: player,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: CastSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('renders nothing on non-Android platforms', (tester) async {
    await pumpCast(tester);
    expect(find.text(l10n.settingsGoogleCast), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
      'SDK path lists routes, shows a session and casts the current track',
      (tester) async {
    sessionAvailable = true;
    MockStreamHandlerEventSink? sessionSink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel(PulsrChannels.castSessionEvents),
      MockStreamHandler.inline(
        onListen: (args, events) { sessionSink = events; },
      ),
    );

    final song = SongsTableData(
      id: 1,
      title: 'Neon Lights',
      artist: 'Artist',
      album: 'Album',
      durationMs: 1000,
      path: '/music/neon.mp3',
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );
    when(() => player.state)
        .thenReturn(PlayerState(playback: PlaybackSlice(currentSong: song)));

    await pumpCast(tester);

    // Empty route list still shows the scanning state first.
    expect(find.text(l10n.scanningCastDevices), findsWidgets);
    expect(calls, contains('session:isAvailable'));
    expect(calls, contains('session:startDiscovery'));

    sessionSink!.success(<String, dynamic>{
      'type': 'routes',
      'routes': <dynamic>[
        <String, dynamic>{'id': 'r1', 'name': 'Den', 'selected': false},
        <String, dynamic>{'id': 'r2', 'name': 'Kitchen', 'selected': true},
      ],
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Den'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);

    // Connect to an unselected route.
    await tester.tap(find.text('Den'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, contains('session:connect'));

    // A live session banner.
    sessionSink!.success(<String, dynamic>{
      'type': 'session',
      'connected': true,
      'deviceName': 'Den',
      'playing': true,
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(l10n.playingOnCast), findsOneWidget);
    expect(find.text(l10n.settingsActiveBadge), findsOneWidget);
    expect(find.text(l10n.castCurrentTrack), findsOneWidget);

    await tester.tap(find.text(l10n.castCurrentTrack));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, contains('session:castLocalFile'));

    await tester.tap(find.text(l10n.stopCast));
    await tester.pump();
    expect(calls.where((c) => c == 'session:disconnect').length,
        greaterThanOrEqualTo(1));

    // Rescan through the session discovery path.
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    expect(
        calls.where((c) => c == 'session:stopDiscovery').length,
        greaterThanOrEqualTo(1));

    await tester.pump(const Duration(seconds: 11));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('mDNS fallback lists devices and casts to one', (tester) async {
    sessionAvailable = false;
    MockStreamHandlerEventSink? deviceSink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel(PulsrChannels.castEvents),
      MockStreamHandler.inline(
        onListen: (args, events) { deviceSink = events; },
      ),
    );

    await pumpCast(tester);

    expect(calls, contains('session:isAvailable'));
    expect(calls, contains('mdns:isSupported'));
    expect(calls, contains('mdns:startDiscovery'));
    expect(find.text(l10n.scanningCastDevices), findsWidgets);

    // Safety timeout ends the scanning spinner and reveals the empty state.
    await tester.pump(const Duration(seconds: 11));
    expect(find.text(l10n.noDevicesSeen), findsOneWidget);

    deviceSink!.success(<String, dynamic>{
      'type': 'devices',
      'devices': <dynamic>[
        <String, dynamic>{
          'id': 'd1',
          'name': 'Chromecast',
          'model': 'Chromecast Ultra',
          'host': '10.0.0.2',
          'port': 8009,
        },
        <String, dynamic>{'id': 'd2', 'name': 'Nest Hub', 'host': '10.0.0.3'},
      ],
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Chromecast'), findsOneWidget);
    expect(find.text('Nest Hub'), findsOneWidget);

    await tester.tap(find.text('Chromecast'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, contains('mdns:castTo'));

    // mDNS rescan path.
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    expect(calls.where((c) => c == 'mdns:stopDiscovery').length,
        greaterThanOrEqualTo(1));

    await tester.pump(const Duration(seconds: 11));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
