import 'dart:io';

String? validateProxyHostAndPort({
  required String host,
  required int port,
}) {
  var h = host.trim();
  // Accept bracketed IPv6 like [::1]: strip brackets for validation
  // (formatting is re-applied at use sites).
  if (h.startsWith('[') && h.endsWith(']') && h.length > 2) {
    h = h.substring(1, h.length - 1);
  }
  // FIX-M4: Strip IPv6 zone id (fe80::1%wlan0) only if prefix is a valid IPv6 address.
  final zoneIndex = h.indexOf('%');
  if (zoneIndex > 0) {
    final candidate = h.substring(0, zoneIndex);
    final parsed = InternetAddress.tryParse(candidate);
    if (parsed != null && parsed.type == InternetAddressType.IPv6) {
      h = candidate;
    }
  }
  if (h.isEmpty) return 'Invalid proxy host format';

  // Fast path: real IP literal (v4 or v6, incl. ::1, full forms, and IPv6-mapped IPv4).
  final asIp = InternetAddress.tryParse(h);
  var isIp = asIp != null;
  if (!isIp) {
    // Check for IPv6-mapped IPv4 addresses (RFC 4291 e.g. ::ffff:192.0.2.1)
    final lower = h.toLowerCase();
    if (lower.startsWith('::ffff:') || lower.startsWith('0:0:0:0:0:ffff:')) {
      final lastColon = h.lastIndexOf(':');
      final ipv4Candidate = h.substring(lastColon + 1);
      final v4Parsed = InternetAddress.tryParse(ipv4Candidate);
      if (v4Parsed != null && v4Parsed.type == InternetAddressType.IPv4) {
        isIp = true;
      }
    }
  }
  final isLocalhost = h == 'localhost' || h == '127.0.0.1' || h == '::1';
  // Single-label LAN hosts (proxy, gateway, router) are valid.
  final isSingleLabel =
      RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$').hasMatch(h);
  final isHostname = RegExp(
          r'^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$')
      .hasMatch(h);
  if (!isIp && !isHostname && !isSingleLabel && !isLocalhost) {
    return 'Invalid proxy host format';
  }
  if (port < 1 || port > 65535) {
    return 'Proxy port must be between 1 and 65535';
  }
  return null;
}
