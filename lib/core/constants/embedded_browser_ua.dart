// lib/core/constants/embedded_browser_ua.dart
//
// Single source of truth for the User-Agent strings used by the embedded
// sign-in / YouTube Music WebView (ytm_web_login_sheet.dart).
//
// KEEP CURRENT — these MUST be bumped to a recent Chrome major version every
// few releases. Google flags embedded-browser sign-ins whose claimed Chrome
// version is stale and shows the "Couldn't sign you in — This browser or app
// may not be secure" block page much more aggressively for old versions.
//   Last bump: Chrome 150 (2026-08).
class EmbeddedBrowserUa {
  EmbeddedBrowserUa._();

  static const int chromeMajor = 150;

  static const String mobile =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$chromeMajor.0.0.0 Mobile Safari/537.36';
  static const String desktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$chromeMajor.0.0.0 Safari/537.36';
}
