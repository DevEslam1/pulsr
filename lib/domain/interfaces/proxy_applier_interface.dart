// lib/domain/interfaces/proxy_applier_interface.dart
// FIX-A2: Dependency inversion interface for network proxy application

/// Contract for synchronizing proxy configuration across Dart HTTP and native engine layers.
abstract class IProxyApplier {
  /// Configures and applies the network proxy settings.
  Future<bool> applyProxy({
    required bool enabled,
    required String host,
    required int port,
    String? username,
    String? password,
  });
}
