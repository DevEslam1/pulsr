import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/home/presentation/widgets/quick_discovery_header.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupAppLocalizations(const Locale('en'));

  GoRouter buildRouter(Widget home) => GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(body: home),
          ),
          GoRoute(
            path: '/ytm-explore',
            builder: (context, state) =>
                const Scaffold(body: Text('ROUTE_YTM_EXPLORE')),
          ),
          GoRoute(
            path: '/downloads',
            builder: (context, state) =>
                const Scaffold(body: Text('ROUTE_DOWNLOADS')),
          ),
          GoRoute(
            path: '/library',
            builder: (context, state) =>
                const Scaffold(body: Text('ROUTE_LIBRARY')),
          ),
          GoRoute(
            path: '/year',
            builder: (context, state) =>
                const Scaffold(body: Text('ROUTE_YEAR')),
          ),
          GoRoute(
            path: '/recents',
            builder: (context, state) =>
                const Scaffold(body: Text('ROUTE_RECENTS')),
          ),
          GoRoute(
            path: '/radio',
            builder: (context, state) =>
                const Scaffold(body: Text('ROUTE_RADIO')),
          ),
          GoRoute(
            path: '/queue',
            builder: (context, state) =>
                const Scaffold(body: Text('ROUTE_QUEUE')),
          ),
        ],
      );

  Future<void> pumpHeader(
    WidgetTester tester,
    QuickDiscoveryHeader header,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: buildRouter(header)),
    );
    await tester.pumpAndSettle();
  }

  group('QuickDiscoveryHeader library mode', () {
    testWidgets('shows every library shortcut plus the common tools',
        (tester) async {
      await pumpHeader(
        tester,
        QuickDiscoveryHeader(onMore: () {}),
      );

      expect(find.text(l10n.artists), findsOneWidget);
      expect(find.text(l10n.albums), findsOneWidget);
      expect(find.text(l10n.folders), findsOneWidget);
      expect(find.text(l10n.decades), findsOneWidget);
      expect(find.text(l10n.downloadsTitle), findsOneWidget);
      expect(find.text(l10n.radioTitle), findsOneWidget);
      expect(find.text(l10n.queue), findsOneWidget);
      expect(find.text(l10n.browseMoreTools), findsOneWidget);
    });

    testWidgets('hides the downloads shortcut when showYtm is false',
        (tester) async {
      await pumpHeader(
        tester,
        QuickDiscoveryHeader(onMore: () {}, showYtm: false),
      );

      expect(find.text(l10n.downloadsTitle), findsNothing);
      expect(find.text(l10n.artists), findsOneWidget);
    });

    testWidgets('navigates to the library when a shortcut is tapped',
        (tester) async {
      await pumpHeader(
        tester,
        QuickDiscoveryHeader(onMore: () {}),
      );

      await tester.tap(find.text(l10n.artists));
      await tester.pumpAndSettle();

      expect(find.text('ROUTE_LIBRARY'), findsOneWidget);
    });
  });

  group('QuickDiscoveryHeader online mode', () {
    testWidgets('swaps library shortcuts for streaming shortcuts',
        (tester) async {
      await pumpHeader(
        tester,
        QuickDiscoveryHeader(onMore: () {}, online: true),
      );

      expect(find.text(l10n.ytmExplore), findsOneWidget);
      expect(find.text(l10n.downloadsTitle), findsOneWidget);
      expect(find.text(l10n.artists), findsNothing);
      expect(find.text(l10n.radioTitle), findsOneWidget);
    });

    testWidgets('navigates to YTM explore when tapped', (tester) async {
      await pumpHeader(
        tester,
        QuickDiscoveryHeader(onMore: () {}, online: true),
      );

      await tester.tap(find.text(l10n.ytmExplore));
      await tester.pumpAndSettle();

      expect(find.text('ROUTE_YTM_EXPLORE'), findsOneWidget);
    });
  });

  group('QuickDiscoveryHeader more tools', () {
    testWidgets('fires onMore without navigating', (tester) async {
      var more = 0;
      await pumpHeader(
        tester,
        QuickDiscoveryHeader(onMore: () => more++),
      );

      await tester.tap(find.text(l10n.browseMoreTools));
      await tester.pump();

      expect(more, 1);
    });
  });

  group('ActiveAudioOutputPill', () {
    testWidgets('renders speaker by default and handles tap', (tester) async {
      var tapped = false;
      await pumpHeader(
        tester,
        QuickDiscoveryHeader(
          showShortcuts: false,
          onAudioOutputTap: () => tapped = true,
        ),
      );

      expect(find.byType(ActiveAudioOutputPill), findsOneWidget);
      expect(find.text(l10n.dspSpeaker), findsOneWidget);

      await tester.tap(find.byType(ActiveAudioOutputPill));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('updates live when SettingsCubit currentOutputDevice changes',
        (tester) async {
      final cubit = _MockSettingsCubit();
      final controller = StreamController<SettingsState>.broadcast();
      addTearDown(() async {
        await controller.close();
        await cubit.close();
      });

      const initialState = SettingsState();
      whenListen(cubit, controller.stream, initialState: initialState);

      await tester.pumpWidget(
        BlocProvider<SettingsCubit>.value(
          value: cubit,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: ActiveAudioOutputPill(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(l10n.dspSpeaker), findsOneWidget);

      // Switch to Bluetooth (LDAC)
      controller.add(
        initialState.copyWith(
          currentOutputDevice: const AudioOutputInfo(
            deviceName: 'Sony WH-1000XM5',
            isUsbDac: false,
            sampleRate: 96000,
            bitDepth: 24,
            isBitPerfectActive: false,
            activeDeviceType: 'bluetooth',
            isBluetooth: true,
            btCodecName: 'LDAC',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LDAC'), findsOneWidget);
      expect(find.text(l10n.dspSpeaker), findsNothing);

      // Switch to USB DAC
      controller.add(
        initialState.copyWith(
          currentOutputDevice: const AudioOutputInfo(
            deviceName: 'FiiO KA13',
            isUsbDac: true,
            sampleRate: 192000,
            sinkSampleRate: 192000,
            bitDepth: 32,
            isBitPerfectActive: true,
            activeDeviceType: 'usb',
            usbDacLabel: 'FiiO KA13',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FiiO KA13 · 192kHz'), findsOneWidget);
      expect(find.text('LDAC'), findsNothing);
    });
  });

  group('CompactSourceScopeSwitcher', () {
    testWidgets('renders local and online segments and notifies on selection',
        (tester) async {
      SourceScope current = SourceScope.local;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CompactSourceScopeSwitcher(
                selectedScope: current,
                onChanged: (next) => setState(() => current = next),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('compact_source_scope_switcher')),
          findsOneWidget);
      expect(find.text(l10n.local), findsOneWidget);
      expect(find.text(l10n.online), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('scope_segment_online')));
      await tester.pumpAndSettle();

      expect(current, SourceScope.online);

      await tester.tap(find.byKey(const ValueKey('scope_segment_local')));
      await tester.pumpAndSettle();

      expect(current, SourceScope.local);
    });

    testWidgets(
        'output pill and scope switcher scale cleanly at 200% text scale',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(2.0),
            ),
            child: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ActiveAudioOutputPill(),
                  CompactSourceScopeSwitcher(
                    selectedScope: SourceScope.local,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('active_audio_output_pill')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('compact_source_scope_switcher')),
          findsOneWidget);
    });

    testWidgets(
        'CompactSourceScopeSwitcher fits 360dp Arabic RTL @ 2.0x text scale without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(2.0),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: CompactSourceScopeSwitcher(
                      selectedScope: SourceScope.online,
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('compact_source_scope_switcher')),
          findsOneWidget);
      final switcherSize = tester
          .getSize(find.byKey(const ValueKey('compact_source_scope_switcher')));
      expect(switcherSize.width, closeTo(320.0, 0.5));
      expect(switcherSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets(
        'spans full content width as 50/50 equal segments on mobile with >=48dp touch targets',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                child: CompactSourceScopeSwitcher(
                  selectedScope: SourceScope.local,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final trackRect = tester
          .getRect(find.byKey(const ValueKey('compact_source_scope_switcher')));
      final localRect =
          tester.getRect(find.byKey(const ValueKey('scope_segment_local')));
      final onlineRect =
          tester.getRect(find.byKey(const ValueKey('scope_segment_online')));

      expect(trackRect.width, closeTo(358.0, 0.5));
      expect(trackRect.height, greaterThanOrEqualTo(48.0));
      expect(localRect.width, closeTo(onlineRect.width, 0.5));
      expect(localRect.height, greaterThanOrEqualTo(48.0));
      expect(onlineRect.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('constrains cleanly to maxWidth 400 on tablet/wide viewports',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(900, 1200)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 24),
                child: CompactSourceScopeSwitcher(
                  selectedScope: SourceScope.online,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final trackSize = tester
          .getSize(find.byKey(const ValueKey('compact_source_scope_switcher')));
      expect(trackSize.width, closeTo(400.0, 0.5));
      expect(trackSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('renders safely inside unbounded horizontal constraints',
        (tester) async {
      SourceScope current = SourceScope.local;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: UnconstrainedBox(
              child: StatefulBuilder(
                builder: (context, setState) => CompactSourceScopeSwitcher(
                  selectedScope: current,
                  onChanged: (next) => setState(() => current = next),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('compact_source_scope_switcher')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('scope_segment_online')));
      await tester.pumpAndSettle();
      expect(current, SourceScope.online);
    });
  });
}
