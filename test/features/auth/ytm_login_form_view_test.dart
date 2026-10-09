// test/features/auth/ytm_login_form_view_test.dart
//
// Covers the login header (signed-out and signed-in variants), the hint banner,
// the refresh action and the overflow menu actions (open web, import cookies,
// clear cache & reset).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/auth/presentation/ytm_web_login_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ytm_webview_test_support.dart';

class MockYtmAccountService extends Mock implements YtmAccountService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockYtmAccountService account;
  late FakePlatformInAppWebViewController fake;

  setUp(() {
    installFakeInAppWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
    account = MockYtmAccountService();
    when(() => account.loginState).thenReturn(ValueNotifier<bool>(false));
    when(() => account.isLoggedIn).thenReturn(false);
    when(() => account.validateSessionDetailed())
        .thenAnswer((_) async => SessionValidationResult.valid);
    when(() => account.validateSession()).thenAnswer((_) async => true);
    when(() => account.clearSessionWebViewCookies()).thenAnswer((_) async {});
    when(() => account.logout()).thenAnswer((_) async {});
    when(() => account.getNativeCookiesFromDomains())
        .thenAnswer((_) async => null);
    getIt.registerSingleton<YtmAccountService>(account);
    fake = fakeWebViewController();
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(ytmHost(const YtmWebLoginSheet()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  void wire(WidgetTester tester) => wireWebViewController(tester, fake);

  testWidgets('signed-out header shows the sign-in copy and controls',
      (tester) async {
    await pumpSheet(tester);
    expect(find.text('Sign in to YouTube Music'), findsOneWidget);
    expect(
        find.text('Connect account to sync Liked Music automatically'),
        findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('signed-in header shows success copy and the login banner',
      (tester) async {
    when(() => account.isLoggedIn).thenReturn(true);
    await pumpSheet(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Logged In Successfully'), findsOneWidget);
    expect(find.text('Account connected! Tap "Done" to finish.'),
        findsOneWidget);
    expect(
        find.text('Login detected! Tap the green "Done" button to complete setup.'),
        findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hint banner appears after the 30s idle timer', (tester) async {
    await pumpSheet(tester);
    expect(
        find.text(
            'Make sure you sign into the correct Google account. Tap "Done" once logged in.'),
        findsNothing);

    await tester.pump(const Duration(seconds: 31));

    expect(
        find.text(
            'Make sure you sign into the correct Google account. Tap "Done" once logged in.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('refresh action reloads the wired controller', (tester) async {
    await pumpSheet(tester);
    wire(tester);
    await tester.tap(find.byTooltip('Refresh page'));
    await tester.pump();
    expect(fake.reloadCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('overflow menu opens YouTube Music web', (tester) async {
    await pumpSheet(tester);
    wire(tester);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Open YouTube Music Web').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.lastLoadedRequest, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('overflow menu opens the manual cookie dialog', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Import Cookies Manually').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('overflow menu clears cookies and resets', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Clear Cache & Reset').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    verify(() => account.clearSessionWebViewCookies()).called(1);
    verify(() => account.logout()).called(1);
    expect(
        find.text('Cookies and cache cleared. Reloading YouTube Music...'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Done with no detected cookies prompts the user',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Please complete sign in on YouTube Music first.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Done pops the route when a signed-in session validates',
      (tester) async {
    when(() => account.isLoggedIn).thenReturn(true);
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      navigatorKey: navKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SizedBox()),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: YtmWebLoginSheet()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Logged In Successfully'), findsOneWidget);
    expect(navKey.currentState!.canPop(), isTrue);
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    verify(() => account.validateSession()).called(1);
    expect(find.byType(YtmWebLoginSheet), findsNothing);
  });
}
