// lib/features/remote_sources/upnp_server_picker_sheet.dart
//
// P1-8 "network parity": the discovery panel for DLNA media servers.
//
// One job: run discovery once, show what answered, and return the server the
// user picked. Persisting the choice belongs to the screen that opened the
// sheet, exactly like [RemoteSourceEditorDialog] returns a draft.
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_error_base.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/widgets/pulsr_progress.dart';
import '../dlna/upnp_device.dart';
import 'remote_sources_strings.dart';
import 'upnp_discovery.dart';

/// Modal list of the media servers found on the current network.
class UpnpServerPickerSheet extends StatefulWidget {
  /// Creates the sheet. [discovery] is injectable for tests.
  const UpnpServerPickerSheet({super.key, this.discovery});

  /// Discovery helper; a private instance is created and closed when omitted.
  final UpnpDiscovery? discovery;

  @override
  State<UpnpServerPickerSheet> createState() => _UpnpServerPickerSheetState();
}

class _UpnpServerPickerSheetState extends State<UpnpServerPickerSheet> {
  late final UpnpDiscovery _discovery;
  late final bool _ownsDiscovery;

  List<UpnpServerDescription> _servers = const <UpnpServerDescription>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsDiscovery = widget.discovery == null;
    _discovery = widget.discovery ?? UpnpDiscovery();
    _search();
  }

  @override
  void dispose() {
    if (_ownsDiscovery) _discovery.close();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final servers = await _discovery.discover();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _loading = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _servers = const <UpnpServerDescription>[];
        _error = e.userMessage;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _servers = const <UpnpServerDescription>[];
        _error = RemoteSourcesStrings.upnpFailed;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.6;
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
                        RemoteSourcesStrings.upnpTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: RemoteSourcesStrings.upnpSearch,
                    onPressed: _loading ? null : _search,
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
            const Divider(height: 1),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final palette = context.palette;
    if (_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 160, child: PulsrProgressBar()),
              const SizedBox(height: 16),
              Text(
                RemoteSourcesStrings.upnpSearching,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, color: palette.error, size: 32),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _search,
                child: const Text(RemoteSourcesStrings.retry),
              ),
            ],
          ),
        ),
      );
    }
    final servers = _servers;
    if (servers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lan_outlined, color: palette.textTertiary, size: 32),
              const SizedBox(height: 12),
              Text(
                RemoteSourcesStrings.upnpNone,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _search,
                child: const Text(RemoteSourcesStrings.retry),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        final authority = server.contentDirectoryControlUrl.authority;
        final details = <String>[
          if (server.modelName != null) server.modelName!,
          if (authority.isNotEmpty) authority,
        ].join(' · ');
        return ListTile(
          minVerticalPadding: 12,
          leading: Icon(Icons.router_outlined, color: palette.accent),
          title: Text(
            server.friendlyName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: details.isEmpty ? null : Text(details),
          trailing: FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(server),
            child: const Text(RemoteSourcesStrings.upnpUse),
          ),
        );
      },
    );
  }
}
