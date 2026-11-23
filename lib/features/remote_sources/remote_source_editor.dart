// lib/features/remote_sources/remote_source_editor.dart
//
// P0-1 "remote sources": the add/edit form.
//
// Returns a [RemoteSourceDraft] through `Navigator.pop`; the caller owns
// persistence so the dialog never touches prefs or the keystore directly.
import 'package:material_ui/material_ui.dart';

import '../../core/theme/aura_theme.dart';
import '../../domain/models/remote_source.dart';
import 'remote_sources_strings.dart';

/// Raw, unvalidated form values collected by [RemoteSourceEditorDialog].
class RemoteSourceDraft {
  /// Creates a draft.
  const RemoteSourceDraft({
    required this.kind,
    required this.displayName,
    required this.host,
    required this.port,
    required this.useTls,
    required this.rootPath,
    required this.username,
    required this.password,
  });

  /// Selected transport.
  final RemoteSourceKind kind;

  /// Display name (may be empty: the host is used instead).
  final String displayName;

  /// Host as typed by the user.
  final String host;

  /// Port as typed by the user.
  final int port;

  /// Whether HTTPS should be used (WebDAV only).
  final bool useTls;

  /// Root folder inside the server.
  final String rootPath;

  /// Login name; empty means anonymous.
  final String username;

  /// Password; empty on an edit means "keep the stored secret".
  final String password;
}

/// Modal form for creating or editing a remote source.
class RemoteSourceEditorDialog extends StatefulWidget {
  /// Creates the dialog. Pass [initial] to edit instead of create.
  const RemoteSourceEditorDialog({
    super.key,
    this.initial,
    this.initialUsername,
  });

  /// Source being edited, or `null` when adding.
  final RemoteSource? initial;

  /// Username read from the credential store (the password is never prefilled).
  final String? initialUsername;

  @override
  State<RemoteSourceEditorDialog> createState() =>
      _RemoteSourceEditorDialogState();
}

class _RemoteSourceEditorDialogState extends State<RemoteSourceEditorDialog> {
  late RemoteSourceKind _kind;
  late bool _useTls;
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _root;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _subsonicUrl;

  String? _hostError;
  String? _portError;
  String? _rootError;
  String? _subsonicUrlError;

  bool get _isEditing => widget.initial != null;

  bool get _isSubsonic => _kind == RemoteSourceKind.subsonic;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _kind = initial?.kind ?? RemoteSourceKind.webdav;
    _useTls =
        initial?.useTls ?? (_kind == RemoteSourceKind.webdav ? true : false);
    _name = TextEditingController(text: initial?.displayName ?? '');
    _host = TextEditingController(text: initial?.host ?? '');
    _port = TextEditingController(
      text: '${initial?.port ?? _kind.defaultPort}',
    );
    _root = TextEditingController(text: initial?.rootPath ?? '/');
    _username = TextEditingController(
      text: widget.initialUsername ?? initial?.username ?? '',
    );
    _password = TextEditingController();
    _subsonicUrl = TextEditingController(
      text: initial == null ? '' : _serverUrlFor(initial),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _root.dispose();
    _username.dispose();
    _password.dispose();
    _subsonicUrl.dispose();
    super.dispose();
  }

  void _handleKindChanged(RemoteSourceKind kind) {
    setState(() {
      final previousDefault = _kind.defaultPort;
      _kind = kind;
      // Only move the port when the user left it at the previous default.
      if (_port.text.trim() == '$previousDefault') {
        _port.text = '${kind.defaultPort}';
      }
      _rootError = null;
      _subsonicUrlError = null;
      if (kind == RemoteSourceKind.subsonic &&
          _subsonicUrl.text.trim().isEmpty) {
        final host = RemoteSource.normalizeHost(_host.text);
        if (host.isNotEmpty) {
          _subsonicUrl.text = _serverUrl(
            host: host,
            port: int.tryParse(_port.text.trim()) ?? kind.defaultPort,
            useTls: true,
            rootPath: _root.text,
          );
        }
      }
    });
  }

  void _submit() {
    if (_isSubsonic) {
      _submitSubsonic();
      return;
    }
    final hostError = RemoteSource.validateHost(_host.text);
    final parsedPort = int.tryParse(_port.text.trim());
    final portError = parsedPort == null
        ? RemoteSourcesStrings.portRange
        : RemoteSource.validatePort(parsedPort);
    final rootText = _root.text.trim();
    String? rootError;
    if (rootText.isEmpty) {
      rootError = RemoteSourcesStrings.rootRequired;
    } else if (_kind == RemoteSourceKind.smb &&
        RemoteSource.normalizeRootPath(rootText) == '/') {
      rootError = RemoteSourcesStrings.shareRequired;
    }
    setState(() {
      _hostError = hostError;
      _portError = portError;
      _rootError = rootError;
    });
    if (hostError != null || portError != null || rootError != null) return;
    Navigator.of(context).pop(
      RemoteSourceDraft(
        kind: _kind,
        displayName: _name.text.trim(),
        host: _host.text,
        port: parsedPort!,
        useTls: _kind == RemoteSourceKind.webdav ? _useTls : false,
        rootPath: rootText,
        username: _username.text.trim(),
        password: _password.text,
      ),
    );
  }

  /// Persists a Subsonic source from its server URL instead of host/port.
  void _submitSubsonic() {
    final parsed = _parseServerUrl(_subsonicUrl.text);
    String? error;
    if (parsed == null) {
      error = RemoteSourcesStrings.subsonicUrlInvalid;
    } else {
      final port =
          parsed.hasPort ? parsed.port : _defaultPortFor(parsed.scheme);
      error = RemoteSource.validateHost(parsed.host) ??
          RemoteSource.validatePort(port);
    }
    setState(() => _subsonicUrlError = error);
    if (error != null || parsed == null) return;
    Navigator.of(context).pop(
      RemoteSourceDraft(
        kind: _kind,
        displayName: _name.text.trim(),
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : _defaultPortFor(parsed.scheme),
        useTls: parsed.scheme == 'https',
        rootPath: parsed.path.isEmpty ? '/' : parsed.path,
        username: _username.text.trim(),
        password: _password.text,
      ),
    );
  }

  /// Parses a server URL, accepting a bare host by assuming `https`.
  ///
  /// Rejects embedded credentials and a query/fragment so the stored record is
  /// exactly the endpoint the token client will sign requests for.
  static Uri? _parseServerUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (!value.contains('://')) value = 'https://$value';
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.trim().isEmpty) return null;
    if (uri.userInfo.isNotEmpty) return null;
    if (uri.hasQuery || uri.hasFragment) return null;
    return uri;
  }

  static int _defaultPortFor(String scheme) =>
      scheme.toLowerCase() == 'https' ? 443 : 80;

  /// Server URL shown when editing an existing source.
  static String _serverUrlFor(RemoteSource source) => _serverUrl(
        host: source.host,
        port: source.port,
        useTls: source.useTls,
        rootPath: source.rootPath,
      );

  /// `scheme://host[:port][/mount]` for the editor field.
  static String _serverUrl({
    required String host,
    required int port,
    required bool useTls,
    required String rootPath,
  }) {
    final scheme = useTls ? 'https' : 'http';
    final literal = RemoteSource.isIpv6Literal(host) ? '[$host]' : host;
    final portPart = port == (useTls ? 443 : 80) ? '' : ':$port';
    final normalizedRoot = RemoteSource.normalizeRootPath(rootPath);
    return '$scheme://$literal$portPart'
        '${normalizedRoot == '/' ? '' : normalizedRoot}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text(
        _isEditing
            ? RemoteSourcesStrings.editorEditTitle
            : RemoteSourcesStrings.editorAddTitle,
      ),
      contentPadding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 0),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<RemoteSourceKind>(
                initialValue: _kind,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: RemoteSourcesStrings.kindLabel,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final kind in RemoteSourceKind.values)
                    if (!kind.isDiscovered)
                      DropdownMenuItem<RemoteSourceKind>(
                        value: kind,
                        child: Text(RemoteSourcesStrings.kindLabelFor(kind)),
                      ),
                ],
                onChanged: (kind) {
                  if (kind != null) _handleKindChanged(kind);
                },
              ),
              const SizedBox(height: 6),
              Text(
                RemoteSourcesStrings.kindDescriptionFor(_kind),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: 16),
              _Field(
                controller: _name,
                label: RemoteSourcesStrings.nameLabel,
                hint: RemoteSourcesStrings.nameHint,
                textInputAction: TextInputAction.next,
              ),
              if (_isSubsonic)
                _Field(
                  controller: _subsonicUrl,
                  label: RemoteSourcesStrings.subsonicUrlLabel,
                  hint: RemoteSourcesStrings.subsonicUrlHint,
                  errorText: _subsonicUrlError,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                )
              else ...[
                _Field(
                  controller: _host,
                  label: RemoteSourcesStrings.hostLabel,
                  hint: RemoteSourcesStrings.hostHint,
                  errorText: _hostError,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                ),
                _Field(
                  controller: _port,
                  label: RemoteSourcesStrings.portLabel,
                  errorText: _portError,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                ),
                if (_kind == RemoteSourceKind.webdav) ...[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(RemoteSourcesStrings.tlsLabel),
                    value: _useTls,
                    onChanged: (value) => setState(() {
                      final currentPort = _port.text.trim();
                      final previousDefault = _useTls ? '443' : '80';
                      _useTls = value;
                      if (currentPort == previousDefault ||
                          currentPort.isEmpty) {
                        _port.text = _useTls ? '443' : '80';
                      }
                    }),
                  ),
                  if (!_useTls)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        RemoteSourcesStrings.cleartextWarning,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                ],
                _Field(
                  controller: _root,
                  label: RemoteSourcesStrings.rootLabel,
                  hint: _kind == RemoteSourceKind.smb
                      ? RemoteSourcesStrings.rootHintShare
                      : RemoteSourcesStrings.rootHint,
                  errorText: _rootError,
                  textInputAction: TextInputAction.next,
                ),
              ],
              _Field(
                controller: _username,
                label: RemoteSourcesStrings.usernameLabel,
                textInputAction: TextInputAction.next,
              ),
              _Field(
                controller: _password,
                label: RemoteSourcesStrings.passwordLabel,
                hint: _isEditing
                    ? RemoteSourcesStrings.passwordKeepHint
                    : null,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(RemoteSourcesStrings.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(RemoteSourcesStrings.save),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.errorText,
    this.keyboardType,
    this.obscureText = false,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? errorText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        autocorrect: false,
        enableSuggestions: !obscureText,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
