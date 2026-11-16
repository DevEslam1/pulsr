// lib/features/remote_sources/remote_browser_sheet.dart
//
// P0-1 "remote sources": the folder browser.
//
// Loads one directory at a time through the provider it is handed, keeps a
// breadcrumb of the path, and reports a file tap to [onPlay]. It never closes
// the provider: the screen that created it owns that lifetime.
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_error_base.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/error_logger.dart';
import '../../core/widgets/pulsr_progress.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';
import 'remote_sources_strings.dart';

/// Bottom sheet that browses one remote source.
class RemoteBrowserSheet extends StatefulWidget {
  /// Creates the browser for [source] over [provider].
  const RemoteBrowserSheet({
    super.key,
    required this.source,
    required this.provider,
    this.onPlay,
  });

  /// Source being browsed (used for the title and the play callback).
  final RemoteSource source;

  /// Provider to list through; owned by the caller.
  final RemoteFsProvider provider;

  /// Invoked when the user taps a file.
  final Future<void> Function(RemoteSource source, String path)? onPlay;

  @override
  State<RemoteBrowserSheet> createState() => _RemoteBrowserSheetState();
}

class _RemoteBrowserSheetState extends State<RemoteBrowserSheet> {
  String _path = '';
  List<RemoteEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String? _playError;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String path) async {
    setState(() {
      _path = path;
      _loading = true;
      _error = null;
      _playError = null;
    });
    try {
      final entries = await widget.provider.list(path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } on AppError catch (e, st) {
      ErrorLogger.log(
        'Remote folder could not be listed: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': widget.source.authority},
      );
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _error = e.userMessage;
        _loading = false;
      });
    } catch (e, st) {
      ErrorLogger.log(
        'Remote folder could not be listed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': widget.source.authority},
      );
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _error = RemoteSourcesStrings.folderLoadFailed;
        _loading = false;
      });
    }
  }

  Future<void> _play(RemoteEntry entry) async {
    final onPlay = widget.onPlay;
    if (onPlay == null) {
      setState(() => _playError = RemoteSourcesStrings.folderLoadFailed);
      return;
    }
    try {
      await onPlay(widget.source, entry.path);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AppError catch (e, st) {
      ErrorLogger.log(
        'Remote file could not be played: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': widget.source.authority},
      );
      if (!mounted) return;
      setState(() => _playError = e.userMessage);
    } catch (e, st) {
      ErrorLogger.log(
        'Remote file could not be played',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': widget.source.authority},
      );
      if (!mounted) return;
      setState(() => _playError = RemoteSourcesStrings.folderLoadFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        widget.source.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: RemoteSourcesStrings.retry,
                    onPressed: _loading ? null : () => _load(_path),
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: RemoteSourcesStrings.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            _Breadcrumbs(path: _path, onNavigate: _loading ? null : _load),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(width: 160, child: PulsrProgressBar()),
      );
    }
    final error = _error;
    if (error != null) {
      return _ErrorState(message: error, onRetry: () => _load(_path));
    }
    final entries = _entries;
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsetsDirectional.all(24),
          child: Text(RemoteSourcesStrings.emptyFolder),
        ),
      );
    }
    return Column(
      children: [
        if (_playError != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 0),
            child: Text(
              _playError!,
              style: TextStyle(color: context.palette.error),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _EntryTile(
                entry: entry,
                onTap: () =>
                    entry.isDirectory ? _load(entry.path) : _play(entry),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final RemoteEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = entry.sizeBytes;
    return ListTile(
      minVerticalPadding: 12,
      leading: Icon(
        entry.isDirectory ? Icons.folder_outlined : Icons.audio_file_outlined,
        color: entry.isDirectory ? palette.accent : palette.textSecondary,
        semanticLabel: entry.isDirectory
            ? RemoteSourcesStrings.folderLabel
            : RemoteSourcesStrings.fileNameUnknown,
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: entry.isDirectory || size == null
          ? null
          : Text(RemoteSourcesStrings.formatBytes(size)),
      trailing: Icon(
        entry.isDirectory ? Icons.chevron_right : Icons.play_arrow,
        color: palette.textTertiary,
      ),
      onTap: onTap,
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.path, required this.onNavigate});

  final String path;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final palette = context.palette;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
      child: Row(
        children: [
          TextButton(
            onPressed: onNavigate == null ? null : () => onNavigate!(''),
            child: const Text(RemoteSourcesStrings.rootCrumb),
          ),
          for (var index = 0; index < segments.length; index++) ...[
            Icon(
              Icons.chevron_right,
              size: 18,
              color: palette.textTertiary,
            ),
            TextButton(
              onPressed: onNavigate == null
                  ? null
                  : () => onNavigate!(segments.take(index + 1).join('/')),
              child: Text(segments[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: palette.error, size: 32),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text(RemoteSourcesStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}
