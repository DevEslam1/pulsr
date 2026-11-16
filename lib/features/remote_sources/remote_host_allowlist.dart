// lib/features/remote_sources/remote_host_allowlist.dart
//
// The narrow bridge between "the user configured this library" and the SSRF
// policy used by the artwork and widget fetchers.
//
// Those fetchers must keep rejecting arbitrary private hosts (a track tag or a
// playlist can carry any URL), but a library the user added on the LAN is a
// deliberate destination: its cover art lives on `192.168.1.10` and asking for
// it is not an attack. This singleton holds exactly the hosts of configured
// sources; it is populated by RemoteSourceStore on load/add and emptied when a
// source disappears. It is *not* consulted by radio, updater or WebView paths.
import '../../core/network/remote_target_policy.dart';
import '../../domain/models/remote_source.dart';

/// Hosts of the user's configured remote libraries.
///
/// Deliberately tiny: one set of lowercase host names derived from
/// [RemoteSource] records. Fetchers pass [hosts] to
/// [RemoteTargetPolicy.classify] as `allowedHostSuffixes`, which matches on a
/// dot boundary (so `evil.example` never matches `example`).
class RemoteHostAllowlist {
  RemoteHostAllowlist();

  /// Process-wide instance used by the fetchers and the source store.
  static final RemoteHostAllowlist instance = RemoteHostAllowlist();

  final Map<String, String> _hostsBySource = <String, String>{};

  /// Every allowed host, lowercased.
  Set<String> get hosts => Set<String>.unmodifiable(_hostsBySource.values);

  /// Whether the allowlist currently carries any host.
  bool get isEmpty => _hostsBySource.isEmpty;

  /// Allows [source]'s host under its source id.
  ///
  /// A blank host is ignored; a source whose host changes replaces the old
  /// entry because the map is keyed by source id.
  void allowSource(RemoteSource source) {
    final host = source.host.trim().toLowerCase();
    if (host.isEmpty) return;
    _hostsBySource[source.id] = host;
  }

  /// Allows [host] without tying it to a source (manual user action).
  ///
  /// Returns whether the host was syntactically usable.
  bool allowHost(String host) {
    final normalized = host.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    _hostsBySource['host:$normalized'] = normalized;
    return true;
  }

  /// Forgets the host registered for [sourceId].
  void removeSource(String sourceId) {
    _hostsBySource.remove(sourceId);
  }

  /// Drops every entry (used by [RemoteSourceStore.reload] and by tests).
  void clear() => _hostsBySource.clear();

  /// Whether [host] is one of the allowed hosts (dot-boundary match).
  bool allows(String host) =>
      RemoteTargetPolicy.hostMatchesAnySuffix(host, hosts);
}
