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
  // Strip IPv6 zone id (fe80::1%wlan0) — valid on link-local addresses.
  final zoneIndex = h.indexOf('%');
  if (zoneIndex > 0) h = h.substring(0, zoneIndex);
  if (h.isEmpty) return 'Invalid proxy host format';

  // Fast path: real IP literal (v4 or v6, incl. ::1 and full forms).
  final asIp = InternetAddress.tryParse(h);
  final isIp = asIp != null;
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
