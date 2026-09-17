// lib/core/utils/ytm_locale.dart
//
// Device-locale YouTube Music region/language params. Previously every login
// and shortcut URL hardcoded `gl=EG&hl=en` (Egypt), forcing Egyptian charts
// and UI language on all users. These helpers derive both from the device
// locale with the same EG/en fallback, so behavior is unchanged for Egyptian
// devices and correct everywhere else.
import 'dart:ui' as ui show PlatformDispatcher;

class YtmLocale {
  static String gl() {
    try {
      final cc = ui.PlatformDispatcher.instance.locale.countryCode;
      if (cc != null && cc.length == 2) return cc.toUpperCase();
    } catch (_) {}
    return 'EG';
  }

  static String hl() {
    try {
      final lang = ui.PlatformDispatcher.instance.locale.languageCode;
      if (lang.isNotEmpty) return lang.toLowerCase();
    } catch (_) {}
    return 'en';
  }

  static String prefCookieValue() => 'f1=50000000&gl=${gl()}&hl=${hl()}';

  /// Returns [url] with `gl`/`hl` ensured (respects existing query params and
  /// never duplicates them).
  static String withLocaleParams(String url) {
    if (url.contains('gl=')) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}gl=${gl()}&hl=${hl()}';
  }

  static String homeUrl() =>
      withLocaleParams('https://music.youtube.com/');
}
