// test/features/auth/ytm_browse_toolbar_test.dart
//
// Covers the browse-mode toolbar: disabled back/forward until history exists,
// the quick-navigation chips, refresh and close actions.
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

  Future<void> pumpBrowse(WidgetTester tester) async {
    await tester.pumpWidget(
        ytmHost(const YtmWebLoginSheet(isBrowseMode: true)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('back and forward are disabled with no history',
      (tester) async {
    await pumpBrowse(tester);
    final back = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_back_ios_new_rounded));
    final forward = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_forward_ios_rounded));
    expect(back.onPressed, isNull);
    expect(forward.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a quick-navigation chip navigates the web view',
      (tester) async {
    await pumpBrowse(tester);
    wireWebViewController(tester, fake);
    await tester.tap(find.text('Explore'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.lastLoadedRequest, isNotNull);
    expect(fake.lastLoadedRequest!.url.toString(), contains('explore'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('refresh reloads the web view', (tester) async {
    await pumpBrowse(tester);
    wireWebViewController(tester, fake);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(fake.reloadCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('close pops the hosting route', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      navigatorKey: navKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SizedBox()),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
        body: YtmWebLoginSheet(isBrowseMode: true),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(YtmWebLoginSheet), findsNothing);
  });
}
