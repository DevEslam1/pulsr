// lib/domain/interfaces/proxy_applier_interface.dart
// FIX-A2: Dependency inversion interface for network proxy application

/// Contract for synchronizing proxy configuration across Dart HTTP and native
/// engine layers.
///
/// Failure semantics:
/// - [applyProxy] returns `true` on success and `false` on failure; it must not
///   throw for an unreachable/misconfigured proxy, so the UI can render a clear
///   retry path instead of an unhandled exception.
///
/// Security contract — credentials MUST be redacted:
/// - [username]/[password] are accepted here but must never be written to a
///   log, telemetry breadcrumb, crash report, or `toString()` output by any
///   implementation. Only the host/port may be logged.
/// - Diagnostics should report `hasAuth` (a boolean) rather than the raw
///   username/password values.
abstract class IProxyApplier {
  /// Configures and applies the network proxy settings.
  ///
  /// Returns `false` on failure. Secrets must be redacted from all logs.
  Future<bool> applyProxy({
    required bool enabled,
    required String host,
    required int port,
    String? username,
    String? password,
  });
}
