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

  static bool _isLocalhost(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';

  bool isBypassed(Uri uri) {
    final host = uri.host.toLowerCase();
    for (final pattern in bypassList) {
      if (pattern == host) return true;
      if (pattern.startsWith('*.')) {
        final domain = pattern.substring(2);
        if (host.endsWith(domain)) return true;
      }
      if (_isLocalhost(pattern) && _isLocalhost(host)) {
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
    final formattedHost = cleanHost.contains(':') ? '[$cleanHost]' : cleanHost;
    switch (type) {
      case AppProxyType.http:
        return 'PROXY $formattedHost:$port; DIRECT';
      case AppProxyType.socks5:
        return 'SOCKS5 $formattedHost:$port; SOCKS $formattedHost:$port; DIRECT';
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

/// An individual proxy item in a multi-proxy pool / list.
class ProxyEntry {
  final String id;
  final String host;
  final int port;
  final String username;
  final String password;
  final AppProxyType type;
  final String label;
  final int? latencyMs;
  final bool? isWorking;
  final String? lastError;
  final bool isTesting;

  const ProxyEntry({
    required this.id,
    required this.host,
    required this.port,
    this.username = '',
    this.password = '',
    this.type = AppProxyType.http,
    this.label = '',
    this.latencyMs,
    this.isWorking,
    this.lastError,
    this.isTesting = false,
  });

  bool get isValid => host.trim().isNotEmpty && port > 0 && port <= 65535;
  bool get hasAuth => username.trim().isNotEmpty;
  String get displayAddress => '$host:$port';
  String get displayTitle =>
      label.trim().isNotEmpty ? label.trim() : displayAddress;

  ProxyConfig toProxyConfig(
      {bool enabled = true, String bypassHosts = 'localhost, 127.0.0.1'}) {
    return ProxyConfig(
      enabled: enabled,
      type: type,
      host: host.trim(),
      port: port,
      username: username.trim(),
      password: password,
      bypassHosts: bypassHosts,
    );
  }

  /// Parses a single raw string line into a [ProxyEntry].
  /// Supported formats:
  /// - `host:port:user:pass`
  /// - `host:port`
  /// - `protocol://user:pass@host:port`
  /// - `user:pass@host:port`
  /// - `host,port,user,pass`
  static ProxyEntry? parse(String rawLine) {
    var line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
      return null;
    }

    AppProxyType detectedType = AppProxyType.http;

    // Handle URI scheme prefix like http:// or socks5://
    if (line.contains('://')) {
      final uri = Uri.tryParse(line);
      if (uri != null && uri.host.isNotEmpty) {
        if (uri.scheme.toLowerCase().contains('socks')) {
          detectedType = AppProxyType.socks5;
        }
        final userInfo = uri.userInfo;
        String user = '';
        String pass = '';
        if (userInfo.isNotEmpty) {
          final userParts = userInfo.split(':');
          user = Uri.decodeComponent(userParts[0]);
          if (userParts.length > 1) {
            pass = Uri.decodeComponent(userParts.sublist(1).join(':'));
          }
        }
        final port = uri.port > 0 ? uri.port : 8080;
        return ProxyEntry(
          id: '${uri.host}:$port:${DateTime.now().microsecondsSinceEpoch}',
          host: uri.host,
          port: port,
          username: user,
          password: pass,
          type: detectedType,
        );
      }
      // If Uri.tryParse failed, strip scheme
      if (line.toLowerCase().startsWith('socks5://') ||
          line.toLowerCase().startsWith('socks://')) {
        detectedType = AppProxyType.socks5;
      }
      line = line.replaceFirst(RegExp(r'^[a-zA-Z0-9]+:\/\/'), '');
    }

    // Handle user:pass@host:port format
    if (line.contains('@')) {
      final lastAtIndex = line.lastIndexOf('@');
      final authPart = line.substring(0, lastAtIndex);
      final serverPart = line.substring(lastAtIndex + 1);

      final authTokens = authPart.split(':');
      final user = authTokens[0].trim();
      final pass = authTokens.length > 1 ? authTokens.sublist(1).join(':') : '';

      final serverTokens = serverPart.split(':');
      final host = serverTokens[0].trim();
      final port = serverTokens.length > 1
          ? int.tryParse(serverTokens[1].trim()) ?? 8080
          : 8080;

      if (host.isNotEmpty) {
        return ProxyEntry(
          id: '$host:$port:${DateTime.now().microsecondsSinceEpoch}',
          host: host,
          port: port,
          username: user,
          password: pass,
          type: detectedType,
        );
      }
    }

    // Handle delimiters: colon, comma, tab, whitespace
    List<String> parts;
    if (line.contains(':')) {
      parts = line.split(':');
    } else if (line.contains(',')) {
      parts = line.split(',');
    } else if (line.contains('\t')) {
      parts = line.split('\t');
    } else {
      parts = line.split(RegExp(r'\s+'));
    }

    parts = parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return null;

    final host = parts[0];
    final port = parts.length > 1 ? (int.tryParse(parts[1]) ?? 8080) : 8080;
    final username = parts.length > 2 ? parts[2] : '';
    final password = parts.length > 3 ? parts.sublist(3).join(':') : '';

    if (host.isEmpty) return null;

    return ProxyEntry(
      id: '$host:$port:${DateTime.now().microsecondsSinceEpoch}',
      host: host,
      port: port,
      username: username,
      password: password,
      type: detectedType,
    );
  }

  /// Parses multiple lines of text into a list of [ProxyEntry].
  static List<ProxyEntry> parseList(String multiLineText) {
    final lines = multiLineText.split(RegExp(r'[\r\n]+'));
    final results = <ProxyEntry>[];
    final seen = <String>{};

    for (int i = 0; i < lines.length; i++) {
      final entry = parse(lines[i]);
      if (entry != null && entry.isValid) {
        final key = '${entry.host}:${entry.port}:${entry.username}';
        if (!seen.contains(key)) {
          seen.add(key);
          results.add(entry.copyWith(
              id: 'proxy_${results.length + 1}_${DateTime.now().millisecondsSinceEpoch}'));
        }
      }
    }
    return results;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'host': host.trim(),
      'port': port,
      'username': username.trim(),
      'password': password,
      'type': type.name,
      'label': label,
      'latencyMs': latencyMs,
      'isWorking': isWorking,
      'lastError': lastError,
    };
  }

  factory ProxyEntry.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String? ?? AppProxyType.http.name;
    final type = AppProxyType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => AppProxyType.http,
    );
    return ProxyEntry(
      id: map['id'] as String? ?? '${map['host']}:${map['port']}',
      host: map['host'] as String? ?? '',
      port: (map['port'] as num?)?.toInt() ?? 8080,
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      type: type,
      label: map['label'] as String? ?? '',
      latencyMs: (map['latencyMs'] as num?)?.toInt(),
      isWorking: map['isWorking'] as bool?,
      lastError: map['lastError'] as String?,
    );
  }

  ProxyEntry copyWith({
    String? id,
    String? host,
    int? port,
    String? username,
    String? password,
    AppProxyType? type,
    String? label,
    int? latencyMs,
    bool? isWorking,
    String? lastError,
    bool? isTesting,
  }) {
    return ProxyEntry(
      id: id ?? this.id,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      type: type ?? this.type,
      label: label ?? this.label,
      latencyMs: latencyMs ?? this.latencyMs,
      isWorking: isWorking ?? this.isWorking,
      lastError: lastError ?? this.lastError,
      isTesting: isTesting ?? this.isTesting,
    );
  }
}
