// lib/features/settings/presentation/proxy_settings_screen.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/proxy_config.dart';
import '../../../core/theme/aura_theme.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

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
    final state = context.read<SettingsCubit>().state;
    _enabled = state.proxyEnabled;
    _type = state.proxyType;
    _hostController = TextEditingController(text: state.proxyHost);
    _portController = TextEditingController(text: state.proxyPort.toString());
    _usernameController = TextEditingController(text: state.proxyUsername);
    _passwordController = TextEditingController(text: state.proxyPassword);
    _bypassController = TextEditingController(text: state.proxyBypassHosts);

    if (widget.initialImportText != null && widget.initialImportText!.isNotEmpty) {
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
    if (_passwordController.text != state.proxyPassword) {
      _passwordController.text = state.proxyPassword;
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
              Icon(Icons.check_circle_rounded, color: context.palette.success, size: 20),
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
        content: Text('Applied preset: $name'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showImportDialog({String? prefilledText}) async {
    final textController = TextEditingController(text: prefilledText ?? '');
    final p = context.palette;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
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
                  Text(
                    'Import Proxies',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['txt', 'csv', 'list', 'conf'],
                        );
                        if (result != null && result.files.isNotEmpty) {
                          final path = result.files.first.path;
                          if (path != null) {
                            final file = File(path);
                            final content = await file.readAsString();
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
                    icon: Icon(Icons.file_open_rounded, size: 18, color: p.accent),
                    label: Text('Pick .txt File', style: TextStyle(color: p.accent)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Paste proxies or import a text file.\nSupported formats: IP:PORT:USER:PASS, IP:PORT, or URL format.',
                style: TextStyle(color: p.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                maxLines: 8,
                style: TextStyle(color: p.textPrimary, fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  hintText: '31.59.20.176:6754:qmyizdto:n5fui7pyec1q\n45.38.107.97:6014:qmyizdto:n5fui7pyec1q\n198.105.121.200:6462',
                  hintStyle: TextStyle(color: p.textTertiary, fontFamily: 'monospace'),
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text('Cancel', style: TextStyle(color: p.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      final raw = textController.text.trim();
                      if (raw.isEmpty) return;
                      final count = await context.read<SettingsCubit>().importProxiesFromText(raw);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.check_circle_rounded, color: p.success, size: 20),
                                const SizedBox(width: 10),
                                Text('Successfully imported $count new proxies'),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Import & Parse', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

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
              'Proxy Settings',
              style: TextStyle(
                color: p.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Import Proxies / Text File',
                icon: Icon(Icons.add_link_rounded, color: p.accent),
                onPressed: () => _showImportDialog(),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.tonal(
                  onPressed: _saveSettings,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accentContainer,
                    foregroundColor: p.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                // Master Switch Card
                _buildMasterToggle(p),
                const SizedBox(height: 20),

                // Multi-Proxy Pool Section
                _buildProxyPoolSection(p, state, proxyList, isTestingAll),
                const SizedBox(height: 20),

                // Protocol Selection Card
                _buildSection(
                  p: p,
                  title: 'ACTIVE PROXY PROTOCOL',
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SegmentedButton<AppProxyType>(
                          segments: const [
                            ButtonSegment(
                              value: AppProxyType.http,
                              label: Text('HTTP / HTTPS'),
                              icon: Icon(Icons.http_rounded),
                            ),
                            ButtonSegment(
                              value: AppProxyType.socks5,
                              label: Text('SOCKS5'),
                              icon: Icon(Icons.shield_outlined),
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
                            backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                              if (states.contains(WidgetState.selected)) {
                                return p.accentContainer;
                              }
                              return p.surface;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                              if (states.contains(WidgetState.selected)) {
                                return p.accent;
                              }
                              return p.textSecondary;
                            }),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _type == AppProxyType.http
                              ? 'Routes standard HTTP and HTTPS web & extractor traffic.'
                              : 'Routes all network streams via SOCKS5 (ideal for Tor, Clash, Shadowsocks).',
                          style: TextStyle(color: p.textTertiary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Active Server Address & Port
                _buildSection(
                  p: p,
                  title: 'ACTIVE SERVER CONFIGURATION',
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _hostController,
                          style: TextStyle(color: p.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Server Host / IP Address',
                            hintText: 'e.g. 127.0.0.1 or proxy.example.com',
                            labelStyle: TextStyle(color: p.textSecondary),
                            hintStyle: TextStyle(color: p.textTertiary),
                            prefixIcon: Icon(Icons.dns_rounded, color: p.accent),
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
                          validator: (value) {
                            if (_enabled && (value == null || value.trim().isEmpty)) {
                              return 'Please enter a proxy host';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _portController,
                          style: TextStyle(color: p.textPrimary),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: 'Port',
                            hintText: 'e.g. 8080, 1080, 7890, 9050',
                            labelStyle: TextStyle(color: p.textSecondary),
                            hintStyle: TextStyle(color: p.textTertiary),
                            prefixIcon: Icon(Icons.numbers_rounded, color: p.accent),
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
                          validator: (value) {
                            if (_enabled) {
                              final port = int.tryParse(value?.trim() ?? '');
                              if (port == null || port <= 0 || port > 65535) {
                                return 'Enter a valid port (1 - 65535)';
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Quick Presets
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'QUICK PRESETS',
                            style: TextStyle(
                              color: p.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _presetChip(
                              label: 'Clash / V2Ray (7890)',
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
                              onTap: () => _applyPreset(
                                name: 'Tor (9050)',
                                type: AppProxyType.socks5,
                                host: '127.0.0.1',
                                port: 9050,
                              ),
                              p: p,
                            ),
                            _presetChip(
                              label: 'Local HTTP (8080)',
                              onTap: () => _applyPreset(
                                name: 'Local HTTP (8080)',
                                type: AppProxyType.http,
                                host: '127.0.0.1',
                                port: 8080,
                              ),
                              p: p,
                            ),
                            _presetChip(
                              label: 'Local SOCKS5 (1080)',
                              onTap: () => _applyPreset(
                                name: 'Local SOCKS5 (1080)',
                                type: AppProxyType.socks5,
                                host: '127.0.0.1',
                                port: 1080,
                              ),
                              p: p,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Authentication (Optional)
                _buildSection(
                  p: p,
                  title: 'AUTHENTICATION (OPTIONAL)',
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _usernameController,
                          style: TextStyle(color: p.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Username',
                            hintText: 'Leave blank if unauthenticated',
                            labelStyle: TextStyle(color: p.textSecondary),
                            hintStyle: TextStyle(color: p.textTertiary),
                            prefixIcon: Icon(Icons.person_outline_rounded, color: p.accent),
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
                        TextFormField(
                          controller: _passwordController,
                          style: TextStyle(color: p.textPrimary),
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Leave blank if unauthenticated',
                            labelStyle: TextStyle(color: p.textSecondary),
                            hintStyle: TextStyle(color: p.textTertiary),
                            prefixIcon: Icon(Icons.lock_outline_rounded, color: p.accent),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: p.textTertiary,
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
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Bypass Hosts
                _buildSection(
                  p: p,
                  title: 'BYPASS HOSTS',
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _bypassController,
                          style: TextStyle(color: p.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Bypass List (comma-separated)',
                            hintText: 'localhost, 127.0.0.1',
                            labelStyle: TextStyle(color: p.textSecondary),
                            hintStyle: TextStyle(color: p.textTertiary),
                            prefixIcon: Icon(Icons.alt_route_rounded, color: p.accent),
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
                        const SizedBox(height: 8),
                        Text(
                          'Connections to these hosts bypass the proxy and connect directly.',
                          style: TextStyle(color: p.textTertiary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
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
                  label: Text(_isTesting ? 'Testing Proxy Connectivity...' : 'Test Active Proxy'),
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
        );
      },
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
                        ),
                  ),
                  if (proxyList.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                TextButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: p.surfaceContainerHigh,
                        title: Text('Clear Proxy Pool?', style: TextStyle(color: p.textPrimary)),
                        content: Text(
                          'Are you sure you want to delete all ${proxyList.length} saved proxies?',
                          style: TextStyle(color: p.textSecondary),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text('Cancel', style: TextStyle(color: p.textSecondary)),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: FilledButton.styleFrom(backgroundColor: p.error),
                            child: const Text('Clear All'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && mounted) {
                      context.read<SettingsCubit>().clearProxyList();
                    }
                  },
                  child: Text('Clear All', style: TextStyle(color: p.error, fontSize: 12)),
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action Buttons Bar (Import, Test All, Sort)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _showImportDialog(),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: const Text('Import / Paste', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    if (proxyList.isNotEmpty) ...[
                      FilledButton.tonalIcon(
                        onPressed: isTestingAll ? null : () => context.read<SettingsCubit>().testAllProxies(),
                        style: FilledButton.styleFrom(
                          backgroundColor: p.surface,
                          foregroundColor: p.accent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: isTestingAll
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
                              )
                            : const Icon(Icons.speed_rounded, size: 16),
                        label: Text(
                          isTestingAll ? 'Testing All...' : 'Test All',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => context.read<SettingsCubit>().sortProxiesByLatency(),
                        style: FilledButton.styleFrom(
                          backgroundColor: p.surface,
                          foregroundColor: p.textPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.sort_rounded, size: 16),
                        label: const Text('Sort by Speed', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                if (proxyList.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.hub_outlined, color: p.textTertiary, size: 36),
                        const SizedBox(height: 10),
                        Text(
                          'No Proxies in Pool',
                          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Import your proxy list (.txt) or paste lines in IP:PORT:USER:PASS format to test and switch seamlessly.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: proxyList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
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
    return InkWell(
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive ? p.accentContainer.withValues(alpha: 0.35) : p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? p.accent : p.hairline,
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // Active / Select indicator
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? p.accent : p.surfaceContainerHigh,
                border: Border.all(
                  color: isActive ? p.accent : p.hairline,
                  width: 2,
                ),
              ),
              child: isActive
                  ? Icon(Icons.check_rounded, color: p.onAccent, size: 18)
                  : null,
            ),
            const SizedBox(width: 12),

            // Proxy Host & Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.displayAddress,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: p.onAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: p.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.type == AppProxyType.socks5 ? 'SOCKS5' : 'HTTP',
                          style: TextStyle(color: p.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (item.hasAuth) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.lock_rounded, size: 12, color: p.accent),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            item.username,
                            style: TextStyle(color: p.textSecondary, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Latency / Status Badge
            _buildLatencyChip(p, item),

            const SizedBox(width: 4),

            // Test Single Button
            IconButton(
              tooltip: 'Test this proxy',
              icon: item.isTesting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
                    )
                  : Icon(Icons.speed_rounded, size: 20, color: p.accent),
              onPressed: item.isTesting ? null : () => context.read<SettingsCubit>().testSingleProxyEntry(item.id),
            ),

            // Delete Button
            IconButton(
              tooltip: 'Remove proxy',
              icon: Icon(Icons.close_rounded, size: 18, color: p.textTertiary),
              onPressed: () => context.read<SettingsCubit>().removeProxyEntry(item.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatencyChip(PulsrPalette p, ProxyEntry item) {
    if (item.isTesting) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: p.accentContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: p.accent),
            ),
            const SizedBox(width: 6),
            Text('Testing', style: TextStyle(color: p.accent, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    if (item.isWorking == true && item.latencyMs != null) {
      final latency = item.latencyMs!;
      final Color color = latency < 3000 ? p.success : (latency < 6000 ? Colors.orange : p.error);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              '${latency}ms',
              style: TextStyle(
                color: color,
                fontSize: 11,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: p.error, size: 12),
            const SizedBox(width: 4),
            Text(
              'Failed',
              style: TextStyle(color: p.error, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: p.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Unverified',
        style: TextStyle(color: p.textTertiary, fontSize: 11),
      ),
    );
  }

  Widget _buildMasterToggle(PulsrPalette p) {
    return Material(
      color: p.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile.adaptive(
        value: _enabled,
        onChanged: (val) {
          setState(() {
            _enabled = val;
            _testResult = null;
          });
        },
        activeTrackColor: p.accent,
        activeThumbColor: Colors.white,
        secondary: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _enabled ? p.accentContainer : p.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _enabled ? Icons.vpn_lock_rounded : Icons.vpn_lock_outlined,
            color: _enabled ? p.accent : p.textSecondary,
            size: 22,
          ),
        ),
        title: const Text(
          'Enable Proxy',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          _enabled
              ? 'All app and YouTube Music/NewPipe requests pass through proxy'
              : 'Direct connection (proxy disabled)',
          style: TextStyle(color: p.textSecondary, fontSize: 12),
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
    required VoidCallback onTap,
    required PulsrPalette p,
  }) {
    return ActionChip(
      label: Text(label, style: TextStyle(color: p.textPrimary, fontSize: 12)),
      backgroundColor: p.surface,
      side: BorderSide(color: p.hairline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onPressed: onTap,
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
