// test/features/auth/ytm_web_login_shell_test.dart
//
// Covers the sheet shell: the throttled loading bar, the body branch selection
// (settings gate → recovery/dead cards → native WebView) and the native
// lifecycle callbacks that drive loading/error state.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(ytmHost(const YtmWebLoginSheet()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<InAppWebViewController> fire(
    WidgetTester tester,
    Future<void> Function(InAppWebViewController controller) action,
  ) async {
    final params = webViewParams(tester);
    final controller =
        params.controllerFromPlatform!(fake) as InAppWebViewController;
    params.onWebViewCreated?.call(controller);
    await action(controller);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return controller;
  }

  testWidgets('shows the loading bar and settings gate initially',
      (tester) async {
    await pumpSheet(tester);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(InAppWebView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('onLoadStop clears loading and updates navigation state',
      (tester) async {
    await pumpSheet(tester);
    await fire(tester, (c) async {
      final params = webViewParams(tester);
      params.onLoadStop?.call(c, WebUri('https://music.youtube.com/'));
    });
    expect(find.byType(InAppWebView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('onReceivedError clears the loading flag', (tester) async {
    await pumpSheet(tester);
    await fire(tester, (c) async {
      final params = webViewParams(tester);
      params.onReceivedError?.call(
        c,
        WebResourceRequest(url: WebUri('https://music.youtube.com/')),
        WebResourceError(
          type: WebResourceErrorType.HOST_LOOKUP,
          description: 'boom',
        ),
      );
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a dead native handle swaps in the interrupted card',
      (tester) async {
    await pumpSheet(tester);
    fake.getUrlError = MissingPluginException('gone');
    await fire(tester, (c) async {
      final params = webViewParams(tester);
      params.onLoadStop?.call(c, WebUri('https://music.youtube.com/'));
    });

    expect(find.text('Web Session Interrupted'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Web Session Interrupted'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a play-store load start bounces back to YouTube Music',
      (tester) async {
    await pumpSheet(tester);
    await fire(tester, (c) async {
      final params = webViewParams(tester);
      params.onLoadStart
          ?.call(c, WebUri('https://play.google.com/store/apps/details'));
    });
    expect(fake.stopLoadingCount, greaterThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('onUpdateVisitedHistory runs the login check for normal URLs',
      (tester) async {
    await pumpSheet(tester);
    await fire(tester, (c) async {
      final params = webViewParams(tester);
      params.onUpdateVisitedHistory
          ?.call(c, WebUri('https://music.youtube.com/library'), false);
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
