// lib/features/settings/presentation/proxy_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/proxy_config.dart';
import '../../../core/theme/aura_theme.dart';
import '../cubit/settings_cubit.dart';

class ProxySettingsScreen extends StatefulWidget {
  const ProxySettingsScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

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

            // Protocol Selection Card
            _buildSection(
              p: p,
              title: 'PROXY PROTOCOL',
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

            // Server Address & Port
            _buildSection(
              p: p,
              title: 'SERVER CONFIGURATION',
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

            // Test Proxy Connection
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
              label: Text(_isTesting ? 'Testing Proxy Connectivity...' : 'Test Connection'),
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
