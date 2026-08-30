// lib/core/constants/embedded_browser_ua.dart
//
// Single source of truth for the User-Agent strings used by the embedded
// sign-in / YouTube Music WebView (ytm_web_login_sheet.dart).
//
// Uses modern Safari (WebKit) User-Agent strings. Google OAuth explicitly blocks
// Android WebView when claiming to be Chrome due to missing Chrome internal
// features / client hints ("This browser or app may not be secure"). Safari
// WebKit User-Agents bypass this embedded-browser restriction cleanly.
class EmbeddedBrowserUa {
  EmbeddedBrowserUa._();

  /// iOS Safari Mobile User-Agent
  static const String mobile =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

  /// macOS Safari Desktop User-Agent
  static const String desktop =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';
}

