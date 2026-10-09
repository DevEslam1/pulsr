// test/features/auth/ytm_web_login_sheet_coverage_test.dart
//
// Extra reachable-branch coverage for YtmWebLoginSheet beyond the two base
// suites: the navigation sandbox's remaining trusted/cancelled hosts, and the
// shell's onLoadStop branches (Google block recovery card, CookieMismatch
// bounce, auth-in-progress no-op, geo-block banner). It reuses the shared
// flutter_inappwebview fakes so no platform channel traffic is needed.
//
// Unreachable from the host (Windows) test runner and documented rather than
// faked:
//   * the Android System-WebView UA probe in _resolveUserAgent()
//     (defaultTargetPlatform != android keeps EmbeddedBrowserUa.mobile), and
//   * the YTM-link branch of FileIntentHandler (compile-time ytmEnabled false).
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
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
    when(() => account.validateSessionDetailed())
        .thenAnswer((_) async => SessionValidationResult.valid);
    when(() => account.clearSessionWebViewCookies()).thenAnswer((_) async {});
    when(() => account.logout()).thenAnswer((_) async {});
    when(() => account.saveSession(any())).thenAnswer((_) async => true);
    when(() => account.getNativeCookiesFromDomains())
        .thenAnswer((_) async => null);
    getIt.registerSingleton<YtmAccountService>(account);
    fake = fakeWebViewController();
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('evaluateNavigation extra hosts', () {
    test('allows the remaining trusted Google hosts', () {
      for (final uri in [
        'https://www.youtube.com/watch?v=x',
        'https://foo.gstatic.com/x',
        'https://foo.googleusercontent.com/x',
        'https://www.googleapis.com/x',
        'https://www.google.com/x',
      ]) {
        expect(YtmWebLoginSheet.evaluateNavigation(Uri.parse(uri)),
            NavigationActionPolicy.ALLOW,
            reason: uri);
      }
    });

    test('cancels play-store redirects smuggled through google.com/url', () {
      expect(
        YtmWebLoginSheet.evaluateNavigation(Uri.parse(
            'https://www.google.com/url?q=https://play.google.com/store')),
        NavigationActionPolicy.CANCEL,
      );
    });
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(ytmHost(const YtmWebLoginSheet()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<InAppWebViewController> fire(
    WidgetTester tester,
    void Function(InAppWebViewController controller) action,
  ) async {
    final params = webViewParams(tester);
    final controller =
        params.controllerFromPlatform!(fake) as InAppWebViewController;
    params.onWebViewCreated?.call(controller);
    action(controller);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return controller;
  }

  testWidgets('a blocked sign-in URL presents the recovery card',
      (tester) async {
    await pumpSheet(tester);
    await fire(tester, (c) {
      final params = webViewParams(tester);
      params.onLoadStop?.call(
          c, WebUri('https://accounts.google.com/v3/signin/blocked'));
    });

    expect(find.byIcon(Icons.gpp_bad_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tv_rounded), findsWidgets);
    expect(find.byIcon(Icons.refresh_rounded), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('recovery card identity switch re-navigates with a new UA',
      (tester) async {
    await pumpSheet(tester);
    await fire(tester, (c) {
      final params = webViewParams(tester);
      params.onLoadStop?.call(
          c, WebUri('https://accounts.google.com/v3/signin/blocked'));
    });

    // Default identity is mobile -> the switch offers Safari Mobile.
    final switchBtn = find.byIcon(Icons.phone_iphone_rounded);
    await tester.ensureVisible(switchBtn);
    await tester.pump();
    await tester.tap(switchBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.setSettingsCount, greaterThan(0));
    expect(fake.lastLoadedRequest, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('recovery card manual retry re-navigates to sign-in',
      (tester) async {
    await pumpSheet(tester);
    await fire(tester, (c) {
      final params = webViewParams(tester);
      params.onLoadStop?.call(
          c, WebUri('https://accounts.google.com/v3/signin/blocked'));
    });

    final retryBtn = find.text('Retry');
    await tester.ensureVisible(retryBtn.first);
    await tester.pump();
    await tester.tap(retryBtn.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.lastLoadedRequest, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a CookieMismatch URL schedules a bounce to the sign-in page',
      (tester) async {
    await pumpSheet(tester);
    await fire(tester, (c) {
      final params = webViewParams(tester);
      params.onLoadStop
          ?.call(c, WebUri('https://accounts.google.com/sorry/index'));
    });

    // Debounced 700ms bounce.
    await tester.pump(const Duration(milliseconds: 800));

    expect(fake.lastLoadedRequest, isNotNull);
    expect(
      fake.lastLoadedRequest!.url.toString(),
      contains('accounts.google.com/v3/signin/identifier'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('an auth-in-progress URL is a no-op (no bounce)',
      (tester) async {
    await pumpSheet(tester);
    await fire(tester, (c) {
      final params = webViewParams(tester);
      params.onLoadStop?.call(
          c, WebUri('https://accounts.google.com/v3/signin/identifier?x=1'));
    });
    await tester.pump(const Duration(milliseconds: 800));

    expect(fake.lastLoadedRequest, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a geo-blocked YouTube Music page shows the bypass banner',
      (tester) async {
    fake.jsResult = true;
    await pumpSheet(tester);
    await fire(tester, (c) {
      final params = webViewParams(tester);
      params.onLoadStop?.call(c, WebUri('https://music.youtube.com/'));
    });

    expect(find.byIcon(Icons.public_off_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('onProgressChanged updates the loading bar without error',
      (tester) async {
    await pumpSheet(tester);
    final params = webViewParams(tester);
    final controller =
        params.controllerFromPlatform!(fake) as InAppWebViewController;
    params.onProgressChanged?.call(controller, 40);
    await tester.pump();
    expect(tester.takeException(), isNull);
    params.onProgressChanged?.call(controller, 100);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}