// lib/core/utils/input_sanitizer.dart

/// Robust security and input sanitization utilities for PULSR.
class InputSanitizer {
  InputSanitizer._();

  static final RegExp _dangerousCharsRegex = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _regexEscapePattern = RegExp(r'[.*+?^${}()|[\]\\]');
  static final RegExp _invalidFileNameCharsRegex = RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]');
  static final RegExp _hostnameRegex = RegExp(
    r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$|^localhost$|^(?:\d{1,3}\.){3}\d{1,3}$|^\[?[a-fA-F0-9:]+\]?$',
  );

  /// Sanitizes playlist names: trims, removes control/null characters,
  /// caps to 100 characters, and falls back to a safe default if blank.
  static String sanitizePlaylistName(String name, {String defaultFallback = 'Untitled Playlist'}) {
    var sanitized = name.replaceAll(_dangerousCharsRegex, '').trim();
    // Normalize any repeated internal whitespace
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ');
    if (sanitized.length > 100) {
      sanitized = sanitized.substring(0, 100).trim();
    }
    return sanitized.isEmpty ? defaultFallback : sanitized;
  }

  /// Trims search queries and escapes regex special characters.
  static String sanitizeSearchQuery(String query) {
    final trimmed = query.trim();
    return trimmed.replaceAllMapped(_regexEscapePattern, (match) => '\\${match.group(0)}');
  }

  /// Validates that a relative file path does not attempt path traversal (`..`)
  /// or escape root boundaries with leading separators.
  static bool isSafeRelativePath(String path) {
    if (path.isEmpty) return false;
    if (path.contains('\x00')) return false;
    // Disallow traversal tokens
    final segments = path.split(RegExp(r'[\\/]'));
    for (final seg in segments) {
      if (seg == '..') return false;
    }
    // Disallow absolute prefixes
    if (path.startsWith('/') || path.startsWith('\\')) return false;
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path)) return false;
    return true;
  }

  /// Sanitizes a filename by replacing reserved filesystem characters:
  /// `/ \ : * ? " < > |` and control characters with an underscore.
  static String sanitizeFileName(String fileName, {String replacement = '_'}) {
    var clean = fileName.replaceAll(_invalidFileNameCharsRegex, replacement).trim();
    while (clean.endsWith('.')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.length > 255) {
      clean = clean.substring(0, 255).trim();
    }
    return clean.isEmpty ? 'unnamed_file' : clean;
  }

  /// Validates cookie header string format before persistence or transmission.
  static bool isValidCookie(String cookie) {
    final trimmed = cookie.trim();
    if (trimmed.isEmpty || trimmed.length > 32768) return false;
    if (trimmed.contains('\x00')) return false;
    // Cookie string must contain at least key=value
    return trimmed.contains('=');
  }

  /// Validates proxy host format (domain name, localhost, IPv4, or IPv6).
  static bool isValidProxyHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty || trimmed.length > 253) return false;
    if (trimmed.contains('..') || trimmed.contains(' ')) return false;
    return _hostnameRegex.hasMatch(trimmed);
  }

  /// Validates proxy port (1 to 65535).
  static bool isValidProxyPort(dynamic port) {
    if (port is int) {
      return port >= 1 && port <= 65535;
    }
    if (port is String) {
      final parsed = int.tryParse(port.trim());
      return parsed != null && parsed >= 1 && parsed <= 65535;
    }
    return false;
  }
}
