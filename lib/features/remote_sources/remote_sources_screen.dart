// lib/features/remote_sources/remote_sources_screen.dart
//
// P0-1 "remote sources": the settings-style screen that owns the whole flow.
//
// It lists/adds/edits/deletes sources, tests a connection and reports the
// round-trip in milliseconds, browses a folder tree with a breadcrumb, and
// shows the disk cache size with a clear action. All persistence goes through
// RemoteSourceStore / RemoteCredentialsStore / RemoteCacheStore, which are
// injectable so a harness can drive the screen without plugins.
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_error_base.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/error_logger.dart';
import '../../core/widgets/pulsr_progress.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';
import 'remote_browser_sheet.dart';
import 'remote_cache_store.dart';
import 'remote_credentials_store.dart';
import 'remote_provider_factory.dart';
import 'remote_source_editor.dart';
import 'remote_source_store.dart';
import 'remote_sources_strings.dart';

/// Manages network libraries and browses them.
class RemoteSourcesScreen extends StatefulWidget {
  /// Creates the screen.
  ///
  /// [onPlay] receives the source and the provider-relative path of the file
  /// the user tapped; the host is expected to make it playable (typically by
  /// registering a provider with `RemoteStreamServer` and opening
  /// `uriFor(source, path)`).
  const RemoteSourcesScreen({
    super.key,
    this.onPlay,
    this.store,
    this.cache,
    this.credentials,
    this.providerFactory,
  });

  /// Called when a file is tapped in the browser.
  final Future<void> Function(RemoteSource source, String path)? onPlay;

  /// Source list storage; defaults to a new [RemoteSourceStore].
  final RemoteSourceStore? store;

  /// Disk cache; defaults to a new [RemoteCacheStore].
  final RemoteCacheStore? cache;

  /// Secure credential storage; defaults to the platform keystore.
  final RemoteCredentialsStore? credentials;

  /// Provider builder; defaults to [createRemoteProvider].
  final RemoteProviderFactory? providerFactory;

  @override
  State<RemoteSourcesScreen> createState() => _RemoteSourcesScreenState();
}

class _SourceStatus {
  const _SourceStatus({this.message, this.latencyMs, this.isError = false});

  final String? message;
  final int? latencyMs;
  final bool isError;
}

class _RemoteSourcesScreenState extends State<RemoteSourcesScreen> {
  late final RemoteSourceStore _store;
  late final RemoteCacheStore _cache;
  late final RemoteCredentialsStore _credentials;
  late final RemoteProviderFactory _factory;

  List<RemoteSource> _sources = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _cacheBusy = false;
  int? _cacheBytes;
  final Map<String, _SourceStatus> _status = <String, _SourceStatus>{};
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? RemoteSourceStore();
    _cache = widget.cache ?? RemoteCacheStore();
    _credentials = widget.credentials ?? RemoteCredentialsStore();
    _factory = widget.providerFactory ?? createRemoteProvider;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _store.ready;
    final bytes = await _cache.currentBytes();
    if (!mounted) return;
    setState(() {
      _sources = _store.list;
      _loading = false;
      _loadFailed = _store.loadFailed;
      _cacheBytes = bytes;
    });
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addSource() async {
    final draft = await showDialog<RemoteSourceDraft>(
      context: context,
      builder: (context) => const RemoteSourceEditorDialog(),
    );
    if (draft == null || !mounted) return;
    await _persistDraft(draft, existing: null);
  }

  Future<void> _editSource(RemoteSource source) async {
    final stored = await _credentials.read(source.id);
    if (!mounted) return;
    final draft = await showDialog<RemoteSourceDraft>(
      context: context,
      builder: (context) => RemoteSourceEditorDialog(
        initial: source,
        initialUsername: stored?.username ?? source.username,
      ),
    );
    if (draft == null || !mounted) return;
    await _persistDraft(draft, existing: source);
  }

  Future<void> _persistDraft(
    RemoteSourceDraft draft, {
    required RemoteSource? existing,
  }) async {
    final hostError = RemoteSource.validateHost(draft.host);
    if (hostError != null) {
      _notify(hostError);
      return;
    }
    final portError = RemoteSource.validatePort(draft.port);
    if (portError != null) {
      _notify(portError);
      return;
    }
    late final RemoteSource source;
    try {
      source = RemoteSource.create(
        kind: draft.kind,
        displayName: draft.displayName,
        host: draft.host,
        port: draft.port,
        rootPath: draft.rootPath,
        useTls: draft.useTls,
        username: draft.username.isEmpty ? null : draft.username,
        // Keeping the id stable keeps the secure-storage slot valid after an
        // edit that changes the host.
        id: existing?.id,
        createdAt: existing?.createdAt,
      );
    } on ArgumentError catch (e, st) {
      ErrorLogger.log(
        'Remote source draft was rejected',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      _notify(e.message.toString());
      return;
    }
    try {
      await _store.add(source);
    } catch (e, st) {
      ErrorLogger.log(
        'Remote source could not be saved',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      _notify(RemoteSourcesStrings.saveFailed);
      return;
    }
    await _writeCredentials(source, draft);
    if (!mounted) return;
    setState(() {
      _sources = _store.list;
      _status.remove(source.id);
    });
  }

  Future<void> _writeCredentials(
    RemoteSource source,
    RemoteSourceDraft draft,
  ) async {
    final username = draft.username.trim();
    try {
      // mergeAndSave keeps a stored password when the field was left blank and
      // never deletes an existing secret. A source that replaces another one
      // by id (same endpoint) therefore keeps working credentials.
      await _credentials.mergeAndSave(
        source.id,
        RemoteCredentials(username: username, password: draft.password),
      );
    } on StateError catch (e, st) {
      ErrorLogger.log(
        'Remote credentials could not be written',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      _notify(RemoteSourcesStrings.credentialsFailed);
    }
  }

  Future<void> _deleteSource(RemoteSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(RemoteSourcesStrings.deleteConfirmTitle(source.displayName)),
        content: const Text(RemoteSourcesStrings.deleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(RemoteSourcesStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(RemoteSourcesStrings.deleteSource),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _store.remove(source.id);
    await _credentials.delete(source.id);
    await _cache.removeSource(source.id);
    if (!mounted) return;
    setState(() {
      _sources = _store.list;
      _status.remove(source.id);
    });
    await _reloadCacheBytes();
  }

  Future<void> _testConnection(RemoteSource source) async {
    setState(() {
      _busy.add(source.id);
      _status.remove(source.id);
    });
    final watch = Stopwatch()..start();
    String? message;
    int? latency;
    var isError = false;
    RemoteFsProvider? provider;
    try {
      final stored = await _credentials.read(source.id);
      provider = _factory(source, stored);
      await provider.list('');
      latency = watch.elapsedMilliseconds;
    } on AppError catch (e, st) {
      ErrorLogger.log(
        'Remote source test failed: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      message = e.userMessage;
      isError = true;
      latency = watch.elapsedMilliseconds;
    } catch (e, st) {
      ErrorLogger.log(
        'Remote source test failed unexpectedly',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      message = e.toString();
      isError = true;
    } finally {
      await provider?.close();
    }
    if (!mounted) return;
    setState(() {
      _busy.remove(source.id);
      _status[source.id] = _SourceStatus(
        message: message,
        latencyMs: latency,
        isError: isError,
      );
    });
  }

  Future<void> _browse(RemoteSource source) async {
    RemoteFsProvider? provider;
    try {
      final stored = await _credentials.read(source.id);
      provider = _factory(source, stored);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: context.palette.surfaceContainer,
        builder: (context) => RemoteBrowserSheet(
          source: source,
          provider: provider!,
          onPlay: widget.onPlay,
        ),
      );
    } on AppError catch (e, st) {
      ErrorLogger.log(
        'Remote browser could not open: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      _notify(e.userMessage);
    } finally {
      await provider?.close();
    }
  }

  Future<void> _reloadCacheBytes() async {
    final bytes = await _cache.currentBytes();
    if (!mounted) return;
    setState(() => _cacheBytes = bytes);
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(RemoteSourcesStrings.clearCache),
        content: const Text(RemoteSourcesStrings.cacheBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(RemoteSourcesStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(RemoteSourcesStrings.clearCache),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cacheBusy = true);
    await _cache.clear();
    if (!mounted) return;
    setState(() {
      _cacheBusy = false;
      _cacheBytes = 0;
    });
    _notify(RemoteSourcesStrings.cacheCleared);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(RemoteSourcesStrings.title),
        actions: [
          IconButton(
            tooltip: RemoteSourcesStrings.addSourceTooltip,
            onPressed: _addSource,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(width: 160, child: PulsrProgressBar()),
      );
    }
    final palette = context.palette;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 32),
      children: [
        Text(
          RemoteSourcesStrings.intro,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: palette.textSecondary),
        ),
        if (_loadFailed) ...[
          const SizedBox(height: 12),
          _InlineBanner(
            message: RemoteSourcesStrings.loadFailed,
            color: palette.error,
            icon: Icons.error_outline,
          ),
        ],
        const SizedBox(height: 16),
        if (_sources.isEmpty)
          _EmptyState(onAdd: _addSource)
        else
          for (final source in _sources)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 12),
              child: _SourceCard(
                source: source,
                status: _status[source.id],
                busy: _busy.contains(source.id),
                onBrowse: () => _browse(source),
                onTest: () => _testConnection(source),
                onEdit: () => _editSource(source),
                onDelete: () => _deleteSource(source),
              ),
            ),
        const SizedBox(height: 8),
        _CacheCard(
          bytes: _cacheBytes,
          busy: _cacheBusy,
          onClear: _clearCache,
        ),
      ],
    );
  }
}

enum _SourceAction { edit, delete }

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.status,
    required this.busy,
    required this.onBrowse,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
  });

  final RemoteSource source;
  final _SourceStatus? status;
  final bool busy;
  final VoidCallback onBrowse;
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final statusText = _statusText();
    final statusColor = _statusColor(palette);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onBrowse,
        contentPadding:
            const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
        leading: Icon(
          source.kind == RemoteSourceKind.smb
              ? Icons.dns_outlined
              : Icons.cloud_outlined,
          color: palette.accent,
        ),
        title: Text(
          source.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${RemoteSourcesStrings.kindLabelFor(source.kind)} · '
              '${source.authority}${source.rootPath}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                statusText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: statusColor),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: RemoteSourcesStrings.testConnectionTooltip,
              onPressed: busy ? null : onTest,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: PulsrProgressBar(height: 18),
                    )
                  : const Icon(Icons.sync),
            ),
            PopupMenuButton<_SourceAction>(
              tooltip: RemoteSourcesStrings.actionsTooltip,
              icon: const Icon(Icons.more_vert),
              onSelected: (action) {
                switch (action) {
                  case _SourceAction.edit:
                    onEdit();
                  case _SourceAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<_SourceAction>(
                  value: _SourceAction.edit,
                  child: Text(RemoteSourcesStrings.editSource),
                ),
                PopupMenuItem<_SourceAction>(
                  value: _SourceAction.delete,
                  child: Text(RemoteSourcesStrings.deleteSource),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusText() {
    if (busy) return RemoteSourcesStrings.testing;
    final current = status;
    if (current == null) return RemoteSourcesStrings.notTested;
    if (current.isError) {
      return current.message ?? RemoteSourcesStrings.notTested;
    }
    final latency = current.latencyMs;
    if (latency == null) return RemoteSourcesStrings.notTested;
    return RemoteSourcesStrings.connectedInLabel(latency);
  }

  Color _statusColor(PulsrPalette palette) {
    if (busy) return palette.textSecondary;
    final current = status;
    if (current == null) return palette.textTertiary;
    if (current.isError) return palette.error;
    return palette.success;
  }
}

class _CacheCard extends StatelessWidget {
  const _CacheCard({
    required this.bytes,
    required this.busy,
    required this.onClear,
  });

  final int? bytes;
  final bool busy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = bytes;
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
        leading: Icon(Icons.sd_storage_outlined, color: palette.textSecondary),
        title: const Text(RemoteSourcesStrings.cacheTitle),
        subtitle: Text(
          busy || size == null
              ? RemoteSourcesStrings.calculating
              : '${RemoteSourcesStrings.formatBytes(size)} · '
                  '${RemoteSourcesStrings.cacheBody}',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: palette.textSecondary),
        ),
        trailing: IconButton(
          tooltip: RemoteSourcesStrings.clearCacheTooltip,
          onPressed: busy ? null : onClear,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.cloud_queue, size: 40, color: palette.textTertiary),
          const SizedBox(height: 12),
          Text(
            RemoteSourcesStrings.emptyTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            RemoteSourcesStrings.emptyBody,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text(RemoteSourcesStrings.addSource),
          ),
        ],
      ),
    );
  }
}

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
