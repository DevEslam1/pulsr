// test/features/auth/ytm_oauth_login_sheet_test.dart
//
// Widget coverage for the captcha-free Google TV device-flow login sheet. The
// sheet talks to the [YtmOAuthService] singleton, whose private http.Client has
// no injection seam, so the success branches (code body, copy row, success
// tile, pop) require a live token exchange and are unreachable from a widget
// test (same limitation documented in test/core/services/ytm_oauth_service_test.dart).
//
// Reachable here: the failed device-code request. Flutter's test binding stubs
// every HTTP call with status 400, which [YtmOAuthService.requestDeviceCode]
// turns into an [OAuthException]; the sheet renders its error body and the
// retry button re-runs the start.
//
// Unreachable:
//   * the generic `catch (e)` branch (browseOauthStartFailed). A transport
//     failure thrown *synchronously* while constructing the service happens
//     inside initState(), so `context.l10n` is read before initState completes
//     and the framework asserts; an asynchronous non-OAuthException cannot be
//     induced without a client injection seam the service does not expose.
//   * `_copy`, the code body and the success tile: all require a real code.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/auth/presentation/ytm_oauth_login_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

Widget host(Widget child) => MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a failed device-code request renders the error body',
      (tester) async {
    await tester.pumpWidget(host(const YtmOAuthLoginSheet()));
    await tester.pumpAndSettle();

    expect(find.byType(YtmOAuthLoginSheet), findsOneWidget);
    // Header always renders.
    expect(find.text('Sign in with Google TV'), findsOneWidget);
    expect(find.text('No captcha - approve on another device'), findsOneWidget);
    // OAuthException branch (status 400 from the test HTTP stub).
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.textContaining('Google returned an error'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
  });

  testWidgets('the retry button re-runs the failed start', (tester) async {
    await tester.pumpWidget(host(const YtmOAuthLoginSheet()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    // Still in the error body after a second failed attempt.
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets('static show opens the sheet in a modal route', (tester) async {
    await tester.pumpWidget(host(Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => YtmOAuthLoginSheet.show(context),
        child: const Text('open-oauth'),
      ),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open-oauth'));
    await tester.pumpAndSettle();

    expect(find.byType(YtmOAuthLoginSheet), findsOneWidget);
    expect(find.text('Sign in with Google TV'), findsOneWidget);
  });
}