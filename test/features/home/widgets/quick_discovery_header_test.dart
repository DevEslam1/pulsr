import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pulsr/features/home/presentation/widgets/quick_discovery_header.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

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
}
