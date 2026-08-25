// lib/core/network/proxy_config.dart

enum AppProxyType {
  http,
  socks5;

  String get displayName {
    switch (this) {
      case AppProxyType.http:
        return 'HTTP / HTTPS';
      case AppProxyType.socks5:
        return 'SOCKS5';
    }
  }
}

class ProxyConfig {
  final bool enabled;
  final AppProxyType type;
  final String host;
  final int port;
  final String username;
  final String password;
  final String bypassHosts;

  const ProxyConfig({
    this.enabled = false,
    this.type = AppProxyType.http,
    this.host = '',
    this.port = 8080,
    this.username = '',
    this.password = '',
    this.bypassHosts = 'localhost, 127.0.0.1',
  });

  bool get isValid => host.trim().isNotEmpty && port > 0 && port <= 65535;

  bool get hasAuth => username.trim().isNotEmpty;

  List<String> get bypassList => bypassHosts
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList();

  bool isBypassed(Uri uri) {
    final host = uri.host.toLowerCase();
    for (final pattern in bypassList) {
      if (pattern == host) return true;
      if (pattern.startsWith('*.')) {
        final domain = pattern.substring(2);
        if (host.endsWith(domain)) return true;
      }
      if (pattern == 'localhost' && (host == 'localhost' || host == '127.0.0.1')) {
        return true;
      }
    }
    return false;
  }

  /// Returns proxy string for Dart `HttpClient.findProxy`
  String toFindProxyString(Uri uri) {
    if (!enabled || !isValid || isBypassed(uri)) {
      return 'DIRECT';
    }
    final cleanHost = host.trim();
    switch (type) {
      case AppProxyType.http:
        return 'PROXY $cleanHost:$port; DIRECT';
      case AppProxyType.socks5:
        return 'SOCKS5 $cleanHost:$port; SOCKS $cleanHost:$port; DIRECT';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'type': type.name,
      'host': host.trim(),
      'port': port,
      'username': username.trim(),
      'password': password,
      'bypassHosts': bypassHosts,
    };
  }

  factory ProxyConfig.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String? ?? AppProxyType.http.name;
    final type = AppProxyType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => AppProxyType.http,
    );
    return ProxyConfig(
      enabled: map['enabled'] as bool? ?? false,
      type: type,
      host: map['host'] as String? ?? '',
      port: (map['port'] as num?)?.toInt() ?? 8080,
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      bypassHosts: map['bypassHosts'] as String? ?? 'localhost, 127.0.0.1',
    );
  }

  ProxyConfig copyWith({
    bool? enabled,
    AppProxyType? type,
    String? host,
    int? port,
    String? username,
    String? password,
    String? bypassHosts,
  }) {
    return ProxyConfig(
      enabled: enabled ?? this.enabled,
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      bypassHosts: bypassHosts ?? this.bypassHosts,
    );
  }
}
