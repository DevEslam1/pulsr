import 'dart:io';

// Cookie-header parsing for YTM sessions, extracted from YtmAccountService (ratchet 01-4).
// The service keeps one-line delegators so existing call sites are unchanged.
class YtmCookieCodec {
  /// Folds a pasted or scraped cookie blob into one well-formed `Cookie` header

  /// Cookies that belong to Google's account-management surface and are never
  static const Set<String> _googleAccountOnlyCookies = {
    'LSID',
    'LSOLH',
    'ACCOUNT_CHOOSER',
    'SMSV',
    'GAPS',
    'OSID',
    '__Secure-OSID',
    'NID',
    'AEC',
    '1P_JAR',
    'OTZ',
    'SEARCH_SAMESITE',
    'COMPASS',
    'S',
    'SSOSID',
  };
  static String normalizeCookieHeader(String raw) {
    const attributeNames = {
      'path',
      'domain',
      'expires',
      'max-age',
      'samesite',
      'priority',
      'partitioned',
      'secure',
      'httponly',
    };
    final ordered = <String, String>{};
    for (final segment in raw.split(RegExp(r'[;\r\n]'))) {
      var pair = segment.trim();
      if (pair.isEmpty) continue;
      if (pair.toLowerCase().startsWith('cookie:')) {
        pair = pair.substring('cookie:'.length).trim();
      }
      final eq = pair.indexOf('=');
      if (eq <= 0) continue; // `Secure`, `HttpOnly`, or a stray value
      final name = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();
      if (name.isEmpty || attributeNames.contains(name.toLowerCase())) continue;
      if (name.contains(RegExp(r'[\s,;]'))) continue; // not a cookie name
      ordered[name] = value;
    }
    return ordered.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
  /// Drops from [raw] the cookies a browser would never send to a YouTube host.
  static String scopeCookiesForYouTube(String raw) {
    final kept = <String>[];
    for (final pair in normalizeCookieHeader(raw).split('; ')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq);
      if (name.toLowerCase().startsWith('__host-')) continue;
      if (_googleAccountOnlyCookies.contains(name)) continue;
      kept.add(pair);
    }
    return kept.join('; ');
  }

  /// Splits a (possibly comma-merged) Set-Cookie header into individual
  static List<String> splitSetCookies(String header) {
    final results = <String>[];
    int start = 0;
    bool inExpires = false;
    for (int i = 0; i < header.length; i++) {
      if (i + 8 <= header.length &&
          header.substring(i, i + 8).toLowerCase() == 'expires=') {
        inExpires = true;
      }
      if (header[i] == ';') {
        inExpires = false;
      }
      if (header[i] == ',' && !inExpires) {
        final nextPart = header.substring(i + 1).trim();
        final eqIdx = nextPart.indexOf('=');
        final semiIdx = nextPart.indexOf(';');
        if (eqIdx > 0 && (semiIdx == -1 || eqIdx < semiIdx)) {
          results.add(header.substring(start, i).trim());
          start = i + 1;
        }
      }
    }
    if (start < header.length) {
      results.add(header.substring(start).trim());
    }
    return results.where((s) => s.isNotEmpty).toList();
  }
  /// Pure cookie-jar merge: applies a raw Set-Cookie header (possibly several
  /// comma-merged cookies) on top of a `k=v; k2=v2` jar. Static so it can be
  /// unit-tested without DI/network.
  static String mergeSetCookieInto(String current, String setCookieHeader) {
    final map = <String, String>{};
    for (final pair in current.split(';')) {
      final parts = pair.trim().split('=');
      if (parts.length >= 2 && parts[0].trim().isNotEmpty) {
        map[parts[0].trim()] = parts.sublist(1).join('=').trim();
      }
    }

    final cookies = splitSetCookies(setCookieHeader);
    for (final cookie in cookies) {
      final segments = cookie.split(';');
      if (segments.isEmpty) continue;

      final nameValue = segments.first.trim();
      final eqIdx = nameValue.indexOf('=');
      if (eqIdx <= 0) continue;

      final name = nameValue.substring(0, eqIdx).trim();
      final value = nameValue.substring(eqIdx + 1).trim();

      bool shouldDelete = false;
      for (int i = 1; i < segments.length; i++) {
        final attr = segments[i].trim().toLowerCase();
        if (attr.startsWith('max-age=')) {
          final maxAge = int.tryParse(attr.substring(8)) ?? 0;
          if (maxAge <= 0) shouldDelete = true;
        }
        if (attr.startsWith('expires=')) {
          try {
            final expires =
                HttpDate.parse(segments[i].trim().substring(8).trim());
            if (expires.isBefore(DateTime.now())) {
              shouldDelete = true;
            }
          } catch (_) {
            final fallbackExp = DateTime.tryParse(attr.substring(8));
            if (fallbackExp != null && fallbackExp.isBefore(DateTime.now())) {
              shouldDelete = true;
            }
          }
        }
      }

      if (shouldDelete) {
        map.remove(name);
      } else {
        map[name] = value;
      }
    }

    return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
  /// Exact-name session-cookie validation: requires an SAPISID-family cookie
  static bool looksLikeSignedInCookies(String rawCookies) {
    String? valueOf(String name) {
      for (final pair in rawCookies.split(';')) {
        final parts = pair.trim().split('=');
        if (parts.length >= 2 && parts[0].trim() == name) {
          final v = parts.sublist(1).join('=').trim();
          if (v.isNotEmpty) return v;
        }
      }
      return null;
    }

    final hasSapisid = valueOf('SAPISID') != null ||
        valueOf('__Secure-3PAPISID') != null ||
        valueOf('__Secure-1PAPISID') != null;
    final hasPsid =
        valueOf('__Secure-3PSID') != null || valueOf('__Secure-1PSID') != null;
    return hasSapisid && hasPsid;
  }
}
