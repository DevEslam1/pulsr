// test/features/auth/ytm_webview_test_support.dart
//
// Shared, deterministic stand-ins for the flutter_inappwebview platform. The
// real plugin has no implementation under `flutter test`, and creating a
// `PlatformInAppWebViewWidget` asserts that `InAppWebViewPlatform.instance` is
// set. These fakes let the YTM login sheet build its native shell and let tests
// drive the native lifecycle callbacks by hand, without any platform channel
// traffic. They live in a non-`_test` file so `flutter test` does not treat
// them as a suite.
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

/// A platform web-view widget that renders out to an inert box. The captured
/// [params] let a test fire `onWebViewCreated` / `onLoadStop` / etc. manually.
class FakePlatformInAppWebView extends PlatformInAppWebViewWidget {
  FakePlatformInAppWebView(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

/// Scriptable stand-in for a native WebView controller. Every networked native
/// call is replaced by a synchronous, inspectable stub.
class FakePlatformInAppWebViewController
    extends PlatformInAppWebViewController {
  FakePlatformInAppWebViewController()
      : super.implementation(
          const PlatformInAppWebViewControllerCreationParams(id: 'fake'),
        );

  /// URL reported by [getUrl]. Defaults to a neutral YouTube Music page.
  WebUri? url = WebUri('https://music.youtube.com/');

  /// When set, [getUrl] throws it (used to simulate a dead native handle).
  Object? getUrlError;

  /// When set, [evaluateJavascript] throws it.
  Object? jsError;

  /// Value returned by [evaluateJavascript].
  dynamic jsResult = '';

  int reloadCount = 0;
  int stopLoadingCount = 0;
  int goBackCount = 0;
  int goForwardCount = 0;
  URLRequest? lastLoadedRequest;
  int setSettingsCount = 0;

  @override
  Future<WebUri?> getUrl() async {
    if (getUrlError != null) throw getUrlError!;
    return url;
  }

  @override
  Future<bool> canGoBack() async => false;

  @override
  Future<bool> canGoForward() async => false;

  @override
  Future<void> setSettings({required InAppWebViewSettings settings}) async {
    setSettingsCount++;
  }

  @override
  Future<void> loadUrl(
      {required URLRequest urlRequest,
      Uri? iosAllowingReadAccessTo,
      WebUri? allowingReadAccessTo}) async {
    lastLoadedRequest = urlRequest;
  }

  @override
  Future<dynamic> evaluateJavascript(
      {required String source, ContentWorld? contentWorld}) async {
    if (jsError != null) throw jsError!;
    return jsResult;
  }

  @override
  Future<void> reload() async {
    reloadCount++;
  }

  @override
  Future<void> stopLoading() async {
    stopLoadingCount++;
  }

  @override
  Future<void> goBack() async {
    goBackCount++;
  }

  @override
  Future<void> goForward() async {
    goForwardCount++;
  }

  @override
  Future<void> clearAllCache({bool includeDiskFiles = true}) async {}

  @override
  void dispose({bool isKeepAlive = false}) {}
}

class FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  FakeInAppWebViewPlatform([FakePlatformInAppWebViewController? controller])
      : fakeController = controller ?? FakePlatformInAppWebViewController();

  final FakePlatformInAppWebViewController fakeController;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) =>
      FakePlatformInAppWebView(params);

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewController(
    PlatformInAppWebViewControllerCreationParams params,
  ) =>
      fakeController;

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      fakeController;
}

/// Installs the fake platform and returns it so tests can reach the scripted
/// controller. Safe to call from every `setUp`.
FakeInAppWebViewPlatform installFakeInAppWebViewPlatform() {
  final platform = FakeInAppWebViewPlatform();
  InAppWebViewPlatform.instance = platform;
  return platform;
}

/// The scripted controller installed by [installFakeInAppWebViewPlatform].
FakePlatformInAppWebViewController fakeWebViewController() =>
    (InAppWebViewPlatform.instance! as FakeInAppWebViewPlatform).fakeController;

/// MaterialApp wrapper carrying the palette theme and localizations the sheet
/// needs.
Widget ytmHost(Widget child) => MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

/// The creation params the sheet handed to the native widget.
PlatformInAppWebViewWidgetCreationParams webViewParams(WidgetTester tester) =>
    tester.widget<InAppWebView>(find.byType(InAppWebView)).platform.params;

/// Wires a scripted native controller into the live sheet by firing the
/// `onWebViewCreated` lifecycle callback, returning the app-facing controller.
InAppWebViewController wireWebViewController(
  WidgetTester tester,
  FakePlatformInAppWebViewController fake,
) {
  final params = webViewParams(tester);
  final controller =
      params.controllerFromPlatform!(fake) as InAppWebViewController;
  params.onWebViewCreated?.call(controller);
  return controller;
}
