String? validateProxyHostAndPort({
  required String host,
  required int port,
}) {
  final isIPv4 = RegExp(
          r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')
      .hasMatch(host);
  final isIPv6 = RegExp(r'^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$')
          .hasMatch(host) ||
      host == '::1' ||
      host.startsWith('fe80:');
  final isHostname = RegExp(
          r'^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$')
      .hasMatch(host);
  final isLocalhost = host == 'localhost' || host == '127.0.0.1';
  if (host.isEmpty || (!isIPv4 && !isIPv6 && !isHostname && !isLocalhost)) {
    return 'Invalid proxy host format';
  }
  if (port < 1 || port > 65535) {
    return 'Proxy port must be between 1 and 65535';
  }
  return null;
}
