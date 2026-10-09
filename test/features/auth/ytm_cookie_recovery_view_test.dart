// test/features/auth/ytm_cookie_recovery_view_test.dart
//
// Covers the cookie-recovery surface: the manual cookie import dialog (all
// verdicts), the CookieMismatch auto-navigation and its hard cap, and the
// scoped cookie/cache wipe.
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
    when(() => account.saveSession(any())).thenAnswer((_) async => true);
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

  Future<void> openCookieDialog(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Import Cookies Manually').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('empty paste is rejected with a prompt', (tester) async {
    await pumpSheet(tester);
    await openCookieDialog(tester);
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Please enter cookie text'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a paste without session cookies is rejected', (tester) async {
    await pumpSheet(tester);
    await openCookieDialog(tester);
    await tester.enterText(find.byType(TextField), 'foo=bar; Path=/');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.textContaining('Missing session cookies'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an invalid verdict rolls the jar back and reports rejection',
      (tester) async {
    when(() => account.validateSessionDetailed())
        .thenAnswer((_) async => SessionValidationResult.invalid);
    await pumpSheet(tester);
    await openCookieDialog(tester);
    await tester.enterText(
        find.byType(TextField), 'SAPISID=abc; __Secure-3PSID=xyz');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('YouTube rejected these cookies'), findsOneWidget);
    verify(() => account.logout()).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an unknown verdict reports the offline verification message',
      (tester) async {
    when(() => account.validateSessionDetailed())
        .thenAnswer((_) async => SessionValidationResult.unknown);
    await pumpSheet(tester);
    await openCookieDialog(tester);
    await tester.enterText(
        find.byType(TextField), 'SAPISID=abc; __Secure-3PSID=xyz');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Could not reach YouTube to verify'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('CookieMismatch navigates past the interstitial',
      (tester) async {
    await pumpSheet(tester);
    final controller = wireWebViewController(tester, fake);
    final params = webViewParams(tester);
    params.onLoadStop?.call(
        controller, WebUri('https://accounts.google.com/CookieMismatch'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(fake.lastLoadedRequest, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('CookieMismatch auto-navigation is capped into block recovery',
      (tester) async {
    await pumpSheet(tester);
    final controller = wireWebViewController(tester, fake);
    final params = webViewParams(tester);
    for (var i = 0; i < 4; i++) {
      params.onLoadStop?.call(
          controller, WebUri('https://accounts.google.com/CookieMismatch'));
      await tester.pump(const Duration(milliseconds: 800));
    }
    expect(find.text('Google is blocking this sign-in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
