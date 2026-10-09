// test/features/auth/ytm_block_recovery_card_test.dart
//
// Covers Google's embedded-browser block recovery: detection via a blocked URL
// and via page text, the recovery card, and each recovery action.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/features/auth/presentation/ytm_web_login_sheet.dart';
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
    when(() => account.cookies).thenReturn(null);
    when(() => account.validateSessionDetailed())
        .thenAnswer((_) async => SessionValidationResult.valid);
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

  Future<InAppWebViewController> pumpBlocked(WidgetTester tester) async {
    await tester.pumpWidget(ytmHost(const YtmWebLoginSheet()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final controller = wireWebViewController(tester, fake);
    final params = webViewParams(tester);
    params.onLoadStop?.call(
        controller, WebUri('https://accounts.google.com/signin/blocked'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return controller;
  }

  testWidgets('a blocked sign-in URL renders the recovery card',
      (tester) async {
    await pumpBlocked(tester);
    expect(find.text('Google is blocking this sign-in'), findsOneWidget);
    expect(find.text('Sign in with Google TV (no captcha)'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Try Safari Mobile'), findsOneWidget);
    expect(find.text('Open YouTube Music web directly'), findsOneWidget);
    expect(find.text('Import Cookies / Token Manually'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Retry clears the session and reloads the sign-in page',
      (tester) async {
    await pumpBlocked(tester);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    verify(() => account.clearSessionWebViewCookies()).called(greaterThan(0));
    expect(find.text('Google is blocking this sign-in'), findsNothing);
    expect(find.byType(InAppWebView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the identity toggle reloads with the next browser identity',
      (tester) async {
    await pumpBlocked(tester);
    await tester.tap(find.text('Try Safari Mobile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Google is blocking this sign-in'), findsNothing);
    expect(find.byType(InAppWebView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opening YouTube Music directly dismisses the recovery card',
      (tester) async {
    await pumpBlocked(tester);
    final target = find.text('Open YouTube Music web directly');
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Google is blocking this sign-in'), findsNothing);
    expect(fake.lastLoadedRequest, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the card can open the manual cookie dialog', (tester) async {
    await pumpBlocked(tester);
    final target = find.text('Import Cookies / Token Manually');
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('block-page text is detected and shown as a block',
      (tester) async {
    await tester.pumpWidget(ytmHost(const YtmWebLoginSheet()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // The block-scan throttle is a real Stopwatch, so real time must pass.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2600)));

    final controller = wireWebViewController(tester, fake);
    fake.url = WebUri('https://accounts.google.com/v3/signin/identifier');
    fake.jsResult = "this browser or app may not be secure";
    final params = webViewParams(tester);
    params.onLoadStop?.call(
        controller, WebUri('https://accounts.google.com/v3/signin/identifier'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Google is blocking this sign-in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a challenge URL is never misread as a block', (tester) async {
    await tester.pumpWidget(ytmHost(const YtmWebLoginSheet()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2600)));

    final controller = wireWebViewController(tester, fake);
    fake.url = WebUri('https://accounts.google.com/signin/challenge/xyz');
    fake.jsResult = "this browser or app may not be secure";
    final params = webViewParams(tester);
    params.onLoadStop?.call(
        controller, WebUri('https://accounts.google.com/signin/challenge/xyz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Google is blocking this sign-in'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
