// lib/features/settings/presentation/proxy_settings_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/proxy_config.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

import '../../../core/utils/error_logger.dart';
class ProxySettingsScreen extends StatefulWidget {
  final String? initialImportText;

  const ProxySettingsScreen({super.key, this.initialImportText});

  @override
  State<ProxySettingsScreen> createState() => _ProxySettingsScreenState();
}

class _ProxySettingsScreenState extends State<ProxySettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late bool _enabled;
  late AppProxyType _type;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _bypassController;

  bool _obscurePassword = true;
  bool _isTesting = false;
  ({bool success, int latencyMs, String? error})? _testResult;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<SettingsCubit>();
    final state = cubit.state;
    _enabled = state.proxyEnabled;
    _type = state.proxyType;
    _hostController = TextEditingController(text: state.proxyHost);
    _portController = TextEditingController(text: state.proxyPort.toString());
    _usernameController = TextEditingController(text: state.proxyUsername);
    _passwordController = TextEditingController();
    _bypassController = TextEditingController(text: state.proxyBypassHosts);

    cubit.getProxyPassword().then((pw) {
      if (mounted && _passwordController.text.isEmpty && pw.isNotEmpty) {
        _passwordController.text = pw;
      }
    });

    if (widget.initialImportText != null &&
        widget.initialImportText!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showImportDialog(prefilledText: widget.initialImportText);
        }
      });
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _bypassController.dispose();
    super.dispose();
  }

  void _syncControllersWithState(SettingsState state) {
    if (_hostController.text != state.proxyHost) {
      _hostController.text = state.proxyHost;
    }
    if (_portController.text != state.proxyPort.toString()) {
      _portController.text = state.proxyPort.toString();
    }
    if (_usernameController.text != state.proxyUsername) {
      _usernameController.text = state.proxyUsername;
    }
    if (_bypassController.text != state.proxyBypassHosts) {
      _bypassController.text = state.proxyBypassHosts;
    }
    _enabled = state.proxyEnabled;
    _type = state.proxyType;
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final port = int.tryParse(_portController.text.trim()) ?? 8080;
    final cubit = context.read<SettingsCubit>();

    await cubit.setProxySettings(
      enabled: _enabled,
      type: _type,
      host: _hostController.text.trim(),
      port: port,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      bypassHosts: _bypassController.text.trim(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: context.palette.success, size: 20),
              const SizedBox(width: 10),
              const Text('Proxy settings saved'),
            ],
          ),
          backgroundColor: context.palette.surfaceContainerHigh,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _runTest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final port = int.tryParse(_portController.text.trim()) ?? 8080;
    final testConfig = ProxyConfig(
      enabled: true,
      type: _type,
      host: _hostController.text.trim(),
      port: port,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      bypassHosts: _bypassController.text.trim(),
    );

    final cubit = context.read<SettingsCubit>();
    final result = await cubit.testProxyConnection(testConfig);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = result;
      });
    }
  }

  void _applyPreset({
    required String name,
    required AppProxyType type,
    required String host,
    required int port,
  }) {
    setState(() {
      _type = type;
      _hostController.text = host;
      _portController.text = port.toString();
      _testResult = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied preset: $name ($host:$port)'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _appendBypassHost(String host) {
    final current = _bypassController.text.trim();
    if (current.isEmpty) {
      _bypassController.text = host;
    } else {
      final list = current.split(',').map((e) => e.trim()).toList();
      if (!list.contains(host)) {
        _bypassController.text = '$current, $host';
      }
    }
  }

  Future<void> _showImportDialog({String? prefilledText}) async {
    final textController = TextEditingController(text: prefilledText ?? '');
    final p = context.palette;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Adaptive.sheetConstraints(ctx).maxWidth,
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: Material(
              color: p.surfaceContainerHigh,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: p.accentContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.file_upload_outlined,
                                    color: p.accent, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Import Proxies',
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: p.textSecondary),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Paste proxy lines or pick a text file. Lines will be parsed automatically.',
                        style: TextStyle(color: p.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final data =
                                  await Clipboard.getData(Clipboard.kTextPlain);
                              if (data != null &&
                                  data.text != null &&
                                  data.text!.isNotEmpty) {
                                textController.text = data.text!;
                              }
                            },
                            icon: Icon(Icons.content_paste_rounded,
                                size: 16, color: p.accent),
                            label: Text('Paste Clipboard',
                                style: TextStyle(
                                    color: p.textPrimary, fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: p.hairline),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final files =
                                    await FilePicker.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: [
                                    'txt',
                                    'csv',
                                    'list',
                                    'conf'
                                  ],
                                );
                                if (files.isNotEmpty) {
                                  final picked = files.first;
                                  String? content;
                                  if (picked.path != null) {
                                    final file = File(picked.path!);
                                    content = await file.readAsString();
                                  } else {
                                    // FIX(file_picker 12): bytes removed — use
                                    // readAsBytes for SAF/cloud providers.
                                    try {
                                      final bytes =
                                          await picked.readAsBytes();
                                      content =
                                          String.fromCharCodes(bytes);
                                    } catch (e, st) {
                                      ErrorLogger.log('fromCharCodes failed', error: e, stackTrace: st, category: 'ProxySettingsScreen');
                                    }
                                  }
                                  if (content != null) {
                                    textController.text = content;
                                  }
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to pick file: $e'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: Icon(Icons.folder_open_rounded,
                                size: 16, color: p.accent),
                            label: Text('Pick File',
                                style: TextStyle(
                                    color: p.textPrimary, fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: p.hairline),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: textController,
                        maxLines: 6,
                        style: TextStyle(
                            color: p.textPrimary,
                            fontFamily: 'monospace',
                            fontSize: 12),
                        decoration: InputDecoration(
                          hintText:
                              '31.59.20.176:6754:username:password\n45.38.107.97:6014\nsocks5://user:pass@127.0.0.1:1080',
                          hintStyle: TextStyle(
                              color: p.textTertiary,
                              fontFamily: 'monospace',
                              fontSize: 12),
                          filled: true,
                          fillColor: p.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: p.hairline),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: p.hairline),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: p.accent, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text('Cancel',
                                style: TextStyle(color: p.textSecondary)),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () async {
                              final raw = textController.text.trim();
                              if (raw.isEmpty) return;
                              final count = await context
                                  .read<SettingsCubit>()
                                  .importProxiesFromText(raw);
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        Icon(Icons.check_circle_rounded,
                                            color: p.success, size: 20),
                                        const SizedBox(width: 10),
                                        Text(
                                            'Successfully imported $count new proxies'),
                                      ],
                                    ),
                                    backgroundColor: p.surfaceContainerHigh,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: p.accent,
                              foregroundColor: p.onAccent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Import & Parse',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final horizontalPad = Adaptive.pagePadding(context);

    return BlocConsumer<SettingsCubit, SettingsState>(
      listener: (context, state) {
        _syncControllersWithState(state);
      },
      builder: (context, state) {
        final proxyList = state.proxyList;
        final isTestingAll = state.isTestingAllProxies;

        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: p.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              context.l10n.proxySettings,
              style: TextStyle(
                color: p.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Import / Paste Proxies',
                icon: Icon(Icons.file_upload_outlined, color: p.accent),
                onPressed: () => _showImportDialog(),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.tonalIcon(
                  onPressed: _saveSettings,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accentContainer,
                    foregroundColor: p.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: Text(context.l10n.save,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding:
                      EdgeInsets.fromLTRB(horizontalPad, 8, horizontalPad, 48),
                  children: [
                    // Master Switch Card
                    _buildMasterToggle(p),
                    const SizedBox(height: 20),

                    // Multi-Proxy Pool Section
                    _buildProxyPoolSection(p, state, proxyList, isTestingAll),
                    const SizedBox(height: 20),

                    // Protocol Selection Card
                    _buildProtocolSection(p),
                    const SizedBox(height: 20),

                    // Active Server Address & Port
                    _buildServerConfigSection(p),
                    const SizedBox(height: 20),

                    // Authentication (Optional)
                    _buildAuthSection(p),
                    const SizedBox(height: 20),

                    // Bypass Hosts
                    _buildBypassSection(p),
                    const SizedBox(height: 24),

                    // Test Active Proxy Connection Button
                    FilledButton.icon(
                      onPressed: _isTesting ? null : _runTest,
                      icon: _isTesting
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: p.onAccent,
                              ),
                            )
                          : const Icon(Icons.speed_rounded),
                      label: Text(
                        _isTesting
                            ? 'Testing Proxy Connectivity...'
                            : 'Test Active Proxy Connection',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                    if (_testResult != null) ...[
                      const SizedBox(height: 16),
                      _buildTestResultCard(p, _testResult!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMasterToggle(PulsrPalette p) {
    return Container(
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _enabled ? p.accent.withValues(alpha: 0.4) : p.hairline,
          width: _enabled ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _enabled ? p.accentContainer : p.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        _enabled ? p.accent.withValues(alpha: 0.3) : p.hairline,
                  ),
                ),
                child: Icon(
                  _enabled ? Icons.vpn_lock_rounded : Icons.vpn_lock_outlined,
                  color: _enabled ? p.accent : p.textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Enable Proxy',
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _enabled
                                ? p.success.withValues(alpha: 0.15)
                                : p.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _enabled ? 'ACTIVE' : 'DISABLED',
                            style: TextStyle(
                              color: _enabled ? p.success : p.textTertiary,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _enabled
                          ? 'Traffic routes through configured proxy'
                          : 'Direct connection (proxy disabled)',
                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _enabled,
                onChanged: (val) {
                  setState(() {
                    _enabled = val;
                    _testResult = null;
                  });
                  context.read<SettingsCubit>().setProxyEnabled(val);
                },
                activeThumbColor: Colors.white,
                activeTrackColor: p.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProxyPoolSection(
    PulsrPalette p,
    SettingsState state,
    List<ProxyEntry> proxyList,
    bool isTestingAll,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 0, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'SAVED PROXY POOL',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: p.textTertiary,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (proxyList.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.accentContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${proxyList.length}',
                        style: TextStyle(
                          color: p.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (proxyList.isNotEmpty)
                InkWell(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: p.surfaceContainerHigh,
                        title: Text('Clear Proxy Pool?',
                            style: TextStyle(color: p.textPrimary)),
                        content: Text(
                          'Are you sure you want to delete all ${proxyList.length} saved proxies?',
                          style: TextStyle(color: p.textSecondary),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text('Cancel',
                                style: TextStyle(color: p.textSecondary)),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: FilledButton.styleFrom(
                                backgroundColor: p.error),
                            child: const Text('Clear All'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && mounted) {
                      unawaited(context.read<SettingsCubit>().clearProxyList());
                    }
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('Clear All',
                        style: TextStyle(
                            color: p.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ),
        Material(
          color: p.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: p.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action Buttons Bar (Import, Test All, Sort)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _showImportDialog(),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                      ),
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: const Text('Import / Paste',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    if (proxyList.isNotEmpty) ...[
                      FilledButton.tonalIcon(
                        onPressed: isTestingAll
                            ? null
                            : () =>
                                context.read<SettingsCubit>().testAllProxies(),
                        style: FilledButton.styleFrom(
                          backgroundColor: p.surface,
                          foregroundColor: p.accent,
                          side: BorderSide(color: p.hairline),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                        ),
                        icon: isTestingAll
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: p.accent),
                              )
                            : const Icon(Icons.speed_rounded, size: 16),
                        label: Text(
                          isTestingAll ? 'Testing All...' : 'Test All Speeds',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => context
                            .read<SettingsCubit>()
                            .sortProxiesByLatency(),
                        style: FilledButton.styleFrom(
                          backgroundColor: p.surface,
                          foregroundColor: p.textPrimary,
                          side: BorderSide(color: p.hairline),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                        ),
                        icon: const Icon(Icons.sort_rounded, size: 16),
                        label: const Text('Sort by Speed',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                if (proxyList.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 28, horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: p.surfaceContainerHigh,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.hub_outlined,
                              color: p.textTertiary, size: 32),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No Proxies in Pool',
                          style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Text(
                            'Import your proxy list (.txt) or paste lines in IP:PORT:USER:PASS format to test latency and switch seamlessly.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 12,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: proxyList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = proxyList[index];
                      final isActive = state.proxyEnabled &&
                          state.proxyHost.trim() == item.host.trim() &&
                          state.proxyPort == item.port;

                      return _buildProxyItemCard(p, item, isActive);
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProxyItemCard(PulsrPalette p, ProxyEntry item, bool isActive) {
    return Material(
      color: isActive ? p.accentContainer.withValues(alpha: 0.3) : p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive ? p.accent : p.hairline,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.read<SettingsCubit>().selectProxyEntry(item);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Activated proxy: ${item.displayAddress}'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Selection Radio, IP:Port, Active Pill, Latency & Actions
              Row(
                children: [
                  // Active Radio / Selection Dot
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? p.accent : Colors.transparent,
                      border: Border.all(
                        color: isActive ? p.accent : p.textTertiary,
                        width: 2,
                      ),
                    ),
                    child: isActive
                        ? Icon(Icons.check_rounded, color: p.onAccent, size: 14)
                        : null,
                  ),
                  const SizedBox(width: 10),

                  // Host:Port display
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.displayAddress,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: p.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: p.onAccent,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Latency Chip
                  _buildLatencyChip(p, item),

                  const SizedBox(width: 4),

                  // Test Button
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'Test latency',
                      icon: item.isTesting
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: p.accent),
                            )
                          : Icon(Icons.speed_rounded,
                              size: 18, color: p.accent),
                      onPressed: item.isTesting
                          ? null
                          : () => context
                              .read<SettingsCubit>()
                              .testSingleProxyEntry(item.id),
                    ),
                  ),

                  // Delete Button
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'Remove proxy',
                      icon: Icon(Icons.close_rounded,
                          size: 16, color: p.textTertiary),
                      onPressed: () => context
                          .read<SettingsCubit>()
                          .removeProxyEntry(item.id),
                    ),
                  ),
                ],
              ),

              // Bottom Details Row: Protocol tag + username (if auth exists)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: p.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.type == AppProxyType.socks5 ? 'SOCKS5' : 'HTTP',
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (item.hasAuth)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: p.accentContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 10, color: p.accent),
                            const SizedBox(width: 3),
                            Text(
                              item.username,
                              style: TextStyle(
                                  color: p.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLatencyChip(PulsrPalette p, ProxyEntry item) {
    if (item.isTesting) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: p.accentContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 8,
              height: 8,
              child:
                  CircularProgressIndicator(strokeWidth: 1.5, color: p.accent),
            ),
            const SizedBox(width: 5),
            Text('Testing',
                style: TextStyle(
                    color: p.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    if (item.isWorking == true && item.latencyMs != null) {
      final latency = item.latencyMs!;
      final Color color = latency < 3000
          ? p.success
          : (latency < 6000 ? Colors.orange : p.error);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              '${latency}ms',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    if (item.isWorking == false) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: p.error, size: 10),
            const SizedBox(width: 3),
            Text(
              'Failed',
              style: TextStyle(
                  color: p.error, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: p.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Unverified',
        style: TextStyle(
            color: p.textTertiary, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildProtocolSection(PulsrPalette p) {
    return _buildSection(
      p: p,
      title: 'ACTIVE PROXY PROTOCOL',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<AppProxyType>(
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero,
                segments: const [
                  ButtonSegment(
                    value: AppProxyType.http,
                    label: Text('HTTP / HTTPS',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    icon: Icon(Icons.http_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: AppProxyType.socks5,
                    label: Text('SOCKS5',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    icon: Icon(Icons.shield_outlined, size: 18),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _type = newSelection.first;
                    _testResult = null;
                  });
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.comfortable,
                  backgroundColor:
                      WidgetStateProperty.resolveWith<Color>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return p.accentContainer;
                    }
                    return p.surface;
                  }),
                  foregroundColor:
                      WidgetStateProperty.resolveWith<Color>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return p.accent;
                    }
                    return p.textSecondary;
                  }),
                  side: WidgetStatePropertyAll(BorderSide(color: p.hairline)),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: p.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _type == AppProxyType.http
                        ? 'Routes standard HTTP & HTTPS web and stream extraction traffic.'
                        : 'Routes network packets via SOCKS5 (recommended for Tor, Clash, Shadowsocks).',
                    style: TextStyle(color: p.textTertiary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerConfigSection(PulsrPalette p) {
    return _buildSection(
      p: p,
      title: 'ACTIVE SERVER CONFIGURATION',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 480;

                final hostField = TextFormField(
                  controller: _hostController,
                  style: TextStyle(color: p.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Server Host / IP Address',
                    hintText: 'e.g. 127.0.0.1 or proxy.example.com',
                    labelStyle: TextStyle(color: p.textSecondary),
                    hintStyle: TextStyle(color: p.textTertiary),
                    prefixIcon:
                        Icon(Icons.dns_rounded, color: p.accent, size: 20),
                    filled: true,
                    fillColor: p.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: p.accent, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                  validator: (value) {
                    if (_enabled && (value == null || value.trim().isEmpty)) {
                      return 'Please enter a proxy host';
                    }
                    return null;
                  },
                );

                final portField = TextFormField(
                  controller: _portController,
                  style: TextStyle(color: p.textPrimary, fontSize: 14),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Port',
                    hintText: 'e.g. 8080',
                    labelStyle: TextStyle(color: p.textSecondary),
                    hintStyle: TextStyle(color: p.textTertiary),
                    prefixIcon:
                        Icon(Icons.numbers_rounded, color: p.accent, size: 20),
                    filled: true,
                    fillColor: p.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: p.accent, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                  validator: (value) {
                    if (_enabled) {
                      final port = int.tryParse(value?.trim() ?? '');
                      if (port == null || port <= 0 || port > 65535) {
                        return 'Invalid port (1-65535)';
                      }
                    }
                    return null;
                  },
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: hostField),
                      const SizedBox(width: 12),
                      Expanded(flex: 1, child: portField),
                    ],
                  );
                }

                return Column(
                  children: [
                    hostField,
                    const SizedBox(height: 14),
                    portField,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Quick Presets Header
            Text(
              'QUICK PRESETS',
              style: TextStyle(
                color: p.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),

            // Presets Wrap
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _presetChip(
                  label: 'Clash / V2Ray (7890)',
                  icon: Icons.alt_route_rounded,
                  onTap: () => _applyPreset(
                    name: 'Clash / V2Ray',
                    type: AppProxyType.http,
                    host: '127.0.0.1',
                    port: 7890,
                  ),
                  p: p,
                ),
                _presetChip(
                  label: 'Tor SOCKS5 (9050)',
                  icon: Icons.shield_outlined,
                  onTap: () => _applyPreset(
                    name: 'Tor',
                    type: AppProxyType.socks5,
                    host: '127.0.0.1',
                    port: 9050,
                  ),
                  p: p,
                ),
                _presetChip(
                  label: 'Local HTTP (8080)',
                  icon: Icons.http_rounded,
                  onTap: () => _applyPreset(
                    name: 'Local HTTP',
                    type: AppProxyType.http,
                    host: '127.0.0.1',
                    port: 8080,
                  ),
                  p: p,
                ),
                _presetChip(
                  label: 'Local SOCKS5 (1080)',
                  icon: Icons.shield_outlined,
                  onTap: () => _applyPreset(
                    name: 'Local SOCKS5',
                    type: AppProxyType.socks5,
                    host: '127.0.0.1',
                    port: 1080,
                  ),
                  p: p,
                ),
                _presetChip(
                  label: 'Shadowsocks (10808)',
                  icon: Icons.cloud_outlined,
                  onTap: () => _applyPreset(
                    name: 'Shadowsocks',
                    type: AppProxyType.socks5,
                    host: '127.0.0.1',
                    port: 10808,
                  ),
                  p: p,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthSection(PulsrPalette p) {
    return _buildSection(
      p: p,
      title: 'AUTHENTICATION (OPTIONAL)',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 480;

            final usernameField = TextFormField(
              controller: _usernameController,
              style: TextStyle(color: p.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Username',
                hintText: 'Leave blank if unauthenticated',
                labelStyle: TextStyle(color: p.textSecondary),
                hintStyle: TextStyle(color: p.textTertiary),
                prefixIcon: Icon(Icons.person_outline_rounded,
                    color: p.accent, size: 20),
                filled: true,
                fillColor: p.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.accent, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            );

            final passwordField = TextFormField(
              controller: _passwordController,
              style: TextStyle(color: p.textPrimary, fontSize: 14),
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Leave blank if unauthenticated',
                labelStyle: TextStyle(color: p.textSecondary),
                hintStyle: TextStyle(color: p.textTertiary),
                prefixIcon:
                    Icon(Icons.lock_outline_rounded, color: p.accent, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: p.textTertiary,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
                filled: true,
                fillColor: p.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.accent, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            );

            if (isWide) {
              return Row(
                children: [
                  Expanded(child: usernameField),
                  const SizedBox(width: 12),
                  Expanded(child: passwordField),
                ],
              );
            }

            return Column(
              children: [
                usernameField,
                const SizedBox(height: 14),
                passwordField,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBypassSection(PulsrPalette p) {
    return _buildSection(
      p: p,
      title: 'BYPASS HOSTS',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _bypassController,
              style: TextStyle(color: p.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Bypass List (comma-separated)',
                hintText: 'localhost, 127.0.0.1, *.local',
                labelStyle: TextStyle(color: p.textSecondary),
                hintStyle: TextStyle(color: p.textTertiary),
                prefixIcon:
                    Icon(Icons.alt_route_rounded, color: p.accent, size: 20),
                filled: true,
                fillColor: p.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.accent, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _bypassChip('localhost', p),
                _bypassChip('127.0.0.1', p),
                _bypassChip('*.local', p),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: p.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Requests matching these hosts will connect directly without routing through proxy.',
                    style: TextStyle(color: p.textTertiary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bypassChip(String host, PulsrPalette p) {
    return InkWell(
      onTap: () => _appendBypassHost(host),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 12, color: p.accent),
            const SizedBox(width: 3),
            Text(host,
                style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required PulsrPalette p,
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 0, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: p.textTertiary,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Material(
          color: p.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: p.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }

  Widget _presetChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required PulsrPalette p,
  }) {
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: p.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: p.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestResultCard(
    PulsrPalette p,
    ({bool success, int latencyMs, String? error}) result,
  ) {
    final isSuccess = result.success;
    final color = isSuccess ? p.success : p.error;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
            color: color,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSuccess ? 'Connection Successful' : 'Connection Failed',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isSuccess
                      ? 'Latency: ${result.latencyMs} ms'
                      : (result.error ?? 'Unknown connection failure'),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
