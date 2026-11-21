// lib/core/network/remote_target_policy.dart
//
// One SSRF policy for every surface that fetches a user- or metadata-supplied
// URL: internet radio, remote libraries, artwork fetchers, scrobblers and the
// integrity checks around them.
//
// Threat model: a URL can come from a playlist import, a share sheet, a radio
// directory, a remote share configuration or a track's embedded metadata. Left
// unchecked, it can reach this device (`localhost`, `127.0.0.1`, `[::1]`), the
// LAN (`10/8`, `172.16/12`, `192.168/16`, `fc00::/7`), link-local services
// (`169.254.0.0/16`, `fe80::/10`) or cloud metadata endpoints, and turn a
// player into a confused deputy.
//
// The policy is deliberately split in two:
//   * [isHttpUrl] is synchronous and syntactic: it rejects non-HTTP schemes,
//     missing hosts and any literal private/loopback host. Use it on the UI
//     path where a DNS answer is not available yet.
//   * [isSafeHost] additionally resolves the name and rejects a public-looking
//     name that resolves into a private range (DNS rebinding). Use it right
//     before opening a connection, when a resolution is affordable.
//
// Both are allow-list friendly: an explicit host allowlist short-circuits the
// network resolution, which is what the login WebView and the cast/SSDP paths
// need (they legitimately talk to link-local devices on the LAN).

import 'dart:io';

/// Classification of a remote target.
enum RemoteTargetVerdict {
  /// Absolute http(s) URL with a routable host.
  allowed,

  /// Empty, relative, or a non-HTTP scheme.
  invalidScheme,

  /// Host is missing or syntactically unusable.
  invalidHost,

  /// Host is (or resolves to) loopback, private, link-local or reserved space.
  privateNetwork,

  /// Host is not in the caller's explicit allowlist.
  notAllowlisted,
}

/// Stateless SSRF policy shared by every remote fetch in the app.
abstract final class RemoteTargetPolicy {
  /// Blocking verdict for [url].
  ///
  /// [requireHttps] is used by surfaces that must never fall back to cleartext
  /// (artwork, updater, credentials-bearing shares). [allowedHostSuffixes]
  /// bypasses the private-network rejection for an explicit, dot-boundary
  /// suffix list (e.g. a cast device on the LAN), and never bypasses
  /// [requireHttps].
  static RemoteTargetVerdict classify(
    String url, {
    bool requireHttps = false,
    Set<String> allowedHostSuffixes = const {},
    bool enforceAllowlist = false,
  }) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return RemoteTargetVerdict.invalidScheme;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return RemoteTargetVerdict.invalidScheme;
    }
    if (requireHttps && scheme != 'https') {
      return RemoteTargetVerdict.invalidScheme;
    }
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) return RemoteTargetVerdict.invalidHost;

    if (allowedHostSuffixes.isNotEmpty &&
        hostMatchesAnySuffix(host, allowedHostSuffixes)) {
      return RemoteTargetVerdict.allowed;
    }
    if (enforceAllowlist) {
      return RemoteTargetVerdict.notAllowlisted;
    }
    if (isUnsafeHost(host)) return RemoteTargetVerdict.privateNetwork;
    return RemoteTargetVerdict.allowed;
  }

  /// True when [url] passes [classify] with the same options.
  static bool isAllowed(
    String url, {
    bool requireHttps = false,
    Set<String> allowedHostSuffixes = const {},
    bool enforceAllowlist = false,
  }) =>
      classify(
        url,
        requireHttps: requireHttps,
        allowedHostSuffixes: allowedHostSuffixes,
        enforceAllowlist: enforceAllowlist,
      ) ==
      RemoteTargetVerdict.allowed;

  /// Convenience wrapper kept for call sites that read better as a predicate.
  static bool isHttpUrl(String url) => isAllowed(url);

  /// True when [host] matches one of [suffixes] on a dot boundary.
  ///
  /// `evil-youtube.com` must not match `youtube.com`, and the bare apex must
  /// match its own suffix. This is the exact rule the login WebView needs.
  static bool hostMatchesAnySuffix(String host, Set<String> suffixes) {
    final lower = host.trim().toLowerCase();
    if (lower.isEmpty) return false;
    for (final suffix in suffixes) {
      final normalized = suffix.trim().toLowerCase();
      if (normalized.isEmpty) continue;
      if (lower == normalized) return true;
      if (lower.endsWith('.$normalized')) return true;
    }
    return false;
  }

  /// True when [host] is a literal in loopback / private / link-local /
  /// reserved space, or a name that can only resolve locally.
  static bool isUnsafeHost(String host) {
    var lower = host.trim().toLowerCase();
    if (lower.startsWith('[') && lower.endsWith(']')) {
      lower = lower.substring(1, lower.length - 1).trim();
    }
    final zoneIdx = lower.indexOf('%');
    if (zoneIdx != -1) lower = lower.substring(0, zoneIdx);
    if (lower.isEmpty) return true;
    if (lower == 'localhost' || lower.endsWith('.localhost')) return true;
    if (lower.endsWith('.local')) return true;

    if (lower.contains(':')) {
      // IPv6 literal (Uri strips the brackets). Reject unspecified/loopback,
      // unique-local, link-local, multicast, site-local, and IPv4-mapped private addresses.
      const loopbacks = {'::', '::1', '0:0:0:0:0:0:0:0', '0:0:0:0:0:0:0:1'};
      if (loopbacks.contains(lower)) return true;
      final embedded = embeddedIpv4(lower);
      if (embedded != null) return isUnsafeIpv4(embedded);
      final firstGroup = lower.split(':').first;
      final value = int.tryParse(firstGroup, radix: 16);
      if (value != null) {
        if ((value & 0xfe00) == 0xfc00) return true; // fc00::/7
        if ((value & 0xffc0) == 0xfe80) return true; // fe80::/10
        if ((value & 0xff00) == 0xff00) return true; // ff00::/8 (multicast)
        if ((value & 0xffc0) == 0xfec0) return true; // fec0::/10 (deprecated site-local)
      }
      return false;
    }

    return isUnsafeIpv4(lower);
  }

  /// True when [ip] is loopback, link-local, unique-local, unspecified, CGNAT
  /// or RFC 1918 private.
  static bool isUnsafeIpAddress(String ip) => isUnsafeHost(ip);

  /// Resolves [host] and rejects any answer in private space.
  ///
  /// Every failure mode is closed: a resolver error *and* an empty answer are
  /// both refused, because neither can prove the target is public. [lookup] is
  /// injectable so tests can simulate rebinding without touching real DNS.
  /// Hosts under the RFC 2606 test domains (`.test`, `.example`, `.invalid`)
  /// skip DNS.
  static Future<bool> isSafeHost(
    String host, {
    Future<List<String>> Function(String host)? lookup,
  }) async {
    final trimmed = host.trim().toLowerCase();
    if (trimmed.isEmpty) return false;
    if (isUnsafeHost(trimmed)) return false;
    if (trimmed.endsWith('.test') ||
        trimmed.endsWith('.example') ||
        trimmed.endsWith('.invalid')) {
      return true;
    }
    if (lookup == null && isIpLiteral(trimmed)) return true;

    try {
      final resolver = lookup ?? defaultDnsLookup;
      final resolved = await resolver(trimmed);
      // No answer is not a public answer: refuse rather than fail open.
      if (resolved.isEmpty) return false;
      for (final ip in resolved) {
        if (isUnsafeHost(ip)) return false;
      }
      return true;
    } catch (_) {
      // A failed lookup cannot prove the target is public; refuse it.
      return false;
    }
  }

  /// True for a syntactically valid IPv4 or IPv6 literal.
  static bool isIpLiteral(String host) {
    var trimmed = host.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
    }
    final zoneIdx = trimmed.indexOf('%');
    if (zoneIdx != -1) trimmed = trimmed.substring(0, zoneIdx);
    if (trimmed.contains(':')) return true;
    final parts = trimmed.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final value = int.tryParse(part);
      return value != null && value >= 0 && value <= 255;
    });
  }

  /// Default resolver; separated so tests never touch real DNS.
  static Future<List<String>> defaultDnsLookup(String host) async {
    try {
      final addresses = await InternetAddress.lookup(host);
      return addresses.map((address) => address.address).toList();
    } on SocketException {
      return const [];
    }
  }

  /// Extracts the IPv4 address embedded in an IPv6 mapped/compatible literal
  /// (`::ffff:a.b.c.d`, `::ffff:hhhh:hhhh`, `::a.b.c.d`) or returns null.
  static String? embeddedIpv4(String lower) {
    final groups = lower.split(':');
    var marker = -1;
    for (var i = 0; i < groups.length; i++) {
      if (groups[i] == 'ffff') {
        marker = i;
        break;
      }
    }
    final prefixEnd = marker == -1 ? groups.length - 1 : marker;
    for (var i = 0; i < prefixEnd; i++) {
      final group = groups[i];
      if (group.isNotEmpty && int.tryParse(group, radix: 16) != 0) return null;
    }
    final rest = groups.sublist(marker == -1 ? groups.length - 1 : marker + 1);
    if (rest.length == 1) {
      return rest.first.contains('.') ? rest.first : null;
    }
    if (rest.length != 2) return null;
    final high = int.tryParse(rest[0].padLeft(4, '0'), radix: 16);
    final low = int.tryParse(rest[1].padLeft(4, '0'), radix: 16);
    if (high == null || low == null || high > 0xffff || low > 0xffff) {
      return null;
    }
    return '${(high >> 8) & 0xff}.${high & 0xff}.'
        '${(low >> 8) & 0xff}.${low & 0xff}';
  }

  /// True when [host] is an IPv4 literal in private, loopback, link-local,
  /// CGNAT or unspecified space.
  static bool isUnsafeIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
      octets.add(value);
    }
    final a = octets[0];
    final b = octets[1];
    if (a == 0) return true; // 0.0.0.0/8 (unspecified)
    if (a == 127) return true; // 127.0.0.0/8
    if (a == 10) return true; // 10.0.0.0/8
    if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
    if (a == 192 && b == 168) return true; // 192.168.0.0/16
    if (a == 169 && b == 254) return true; // 169.254.0.0/16
    if (a == 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10
    if (a >= 224) return true; // 224.0.0.0/4 multicast, 240.0.0.0/4 reserved, 255.255.255.255
    return false;
  }
}
