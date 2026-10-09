// test/features/auth/ytm_web_login_sheet_test.dart
//
// Covers the public surface of YtmWebLoginSheet: the hardened settings builder,
// the navigation sandbox policy, and the top-level shell states (loading,
// normal WebView, browse mode, route dismissal).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/constants/embedded_browser_ua.dart';
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
  late ValueNotifier<bool> loginState;

  setUp(() {
    installFakeInAppWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
    account = MockYtmAccountService();
    loginState = ValueNotifier<bool>(false);
    when(() => account.loginState).thenReturn(loginState);
    when(() => account.isLoggedIn).thenReturn(false);
    when(() => account.validateSessionDetailed())
        .thenAnswer((_) async => SessionValidationResult.valid);
    when(() => account.clearSessionWebViewCookies()).thenAnswer((_) async {});
    when(() => account.logout()).thenAnswer((_) async {});
    when(() => account.getNativeCookiesFromDomains())
        .thenAnswer((_) async => null);
    getIt.registerSingleton<YtmAccountService>(account);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    bool isBrowseMode = false,
    String? initialUrl,
  }) async {
    await tester.pumpWidget(ytmHost(YtmWebLoginSheet(
      isBrowseMode: isBrowseMode,
      initialUrl: initialUrl,
    )));
    // Flush the async settings bootstrap.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('buildDefaultSettings', () {
    test('hardens the WebView sandbox', () {
      final s = YtmWebLoginSheet.buildDefaultSettings();
      expect(s.userAgent, EmbeddedBrowserUa.mobile);
      expect(s.javaScriptEnabled, isTrue);
      expect(s.javaScriptCanOpenWindowsAutomatically, isFalse);
      expect(s.allowFileAccess, isFalse);
      expect(s.allowContentAccess, isFalse);
      expect(s.allowFileAccessFromFileURLs, isFalse);
      expect(s.allowUniversalAccessFromFileURLs, isFalse);
      expect(s.thirdPartyCookiesEnabled, isTrue);
      expect(s.sharedCookiesEnabled, isTrue);
      expect(s.domStorageEnabled, isTrue);
      expect(s.databaseEnabled, isTrue);
      expect(s.geolocationEnabled, isFalse);
      expect(s.mediaPlaybackRequiresUserGesture, isFalse);
      expect(s.useShouldOverrideUrlLoading, isTrue);
      expect(s.mixedContentMode,
          MixedContentMode.MIXED_CONTENT_NEVER_ALLOW);
      expect(s.requestedWithHeaderOriginAllowList, isEmpty);
    });

    test('accepts an explicit user agent', () {
      final s = YtmWebLoginSheet.buildDefaultSettings(userAgent: 'custom/1');
      expect(s.userAgent, 'custom/1');
    });
  });

  group('evaluateNavigation', () {
    test('allows null and trusted https endpoints', () {
      expect(YtmWebLoginSheet.evaluateNavigation(null),
          NavigationActionPolicy.ALLOW);
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('https://music.youtube.com/')),
          NavigationActionPolicy.ALLOW);
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('https://accounts.google.com/v3/signin')),
          NavigationActionPolicy.ALLOW);
      expect(YtmWebLoginSheet.evaluateNavigation(Uri.parse('https://youtu.be/x')),
          NavigationActionPolicy.ALLOW);
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('https://foo.googleapis.com/x')),
          NavigationActionPolicy.ALLOW);
      expect(YtmWebLoginSheet.evaluateNavigation(Uri.parse('about:blank')),
          NavigationActionPolicy.ALLOW);
    });

    test('cancels script, file, data and blob schemes', () {
      for (final uri in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'data:text/html,x',
        'blob:https://x/y',
      ]) {
        expect(YtmWebLoginSheet.evaluateNavigation(Uri.parse(uri)),
            NavigationActionPolicy.CANCEL,
            reason: uri);
      }
    });

    test('cancels market, intent and play store links', () {
      for (final uri in [
        'market://details?id=x',
        'intent://x#Intent;end',
        'https://play.google.com/store/apps/details?id=x',
      ]) {
        expect(YtmWebLoginSheet.evaluateNavigation(Uri.parse(uri)),
            NavigationActionPolicy.CANCEL,
            reason: uri);
      }
    });

    test('cancels untrusted and non-https hosts', () {
      expect(YtmWebLoginSheet.evaluateNavigation(Uri.parse('https://evil.com')),
          NavigationActionPolicy.CANCEL);
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('http://music.youtube.com/')),
          NavigationActionPolicy.CANCEL);
    });
  });

  testWidgets('shows the loading body before settings resolve',
      (tester) async {
    await tester.pumpWidget(ytmHost(const YtmWebLoginSheet()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Sign in to YouTube Music'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('renders the native web view after bootstrap', (tester) async {
    await pumpSheet(tester);
    expect(find.byType(InAppWebView), findsOneWidget);
    expect(find.text('Sign in to YouTube Music'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('browse mode renders its toolbar and nav chips',
      (tester) async {
    await pumpSheet(tester, isBrowseMode: true);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Forward'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('close button pops the hosting route', (tester) async {
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
    expect(find.byType(YtmWebLoginSheet), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(YtmWebLoginSheet), findsNothing);
  });
}
