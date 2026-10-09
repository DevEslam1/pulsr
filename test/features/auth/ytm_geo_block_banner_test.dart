// test/features/auth/ytm_geo_block_banner_test.dart
//
// Covers the region-restriction banner: detection through the injected JS scan,
// the Force-Egypt bypass and the YouTube Web fallback.
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

  Future<void> fireYtmLoad(WidgetTester tester) async {
    await tester.pumpWidget(ytmHost(const YtmWebLoginSheet()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final controller = wireWebViewController(tester, fake);
    final params = webViewParams(tester);
    params.onLoadStop?.call(controller, WebUri('https://music.youtube.com/'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('a geo-restricted page shows the banner', (tester) async {
    fake.url = WebUri('https://music.youtube.com/');
    fake.jsResult = true;
    await fireYtmLoad(tester);

    expect(
        find.text('YouTube Music is restricted in your region'), findsOneWidget);
    expect(find.text('Force Egypt Mode'), findsOneWidget);
    expect(find.text('Open YouTube Web'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Force Egypt Mode clears the banner and reloads',
      (tester) async {
    fake.url = WebUri('https://music.youtube.com/');
    fake.jsResult = true;
    await fireYtmLoad(tester);

    await tester.tap(find.text('Force Egypt Mode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('YouTube Music is restricted in your region'),
        findsNothing);
    expect(fake.lastLoadedRequest, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the YouTube Web fallback navigates away', (tester) async {
    fake.url = WebUri('https://music.youtube.com/');
    fake.jsResult = true;
    await fireYtmLoad(tester);

    await tester.tap(find.text('Open YouTube Web'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.lastLoadedRequest!.url.toString(), contains('youtube.com'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a non-restricted page shows no banner', (tester) async {
    fake.url = WebUri('https://music.youtube.com/');
    fake.jsResult = false;
    await fireYtmLoad(tester);
    expect(find.text('YouTube Music is restricted in your region'),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a JS failure is swallowed and shows no banner', (tester) async {
    fake.url = WebUri('https://music.youtube.com/');
    fake.jsError = StateError('no js');
    await fireYtmLoad(tester);
    expect(find.text('YouTube Music is restricted in your region'),
        findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
