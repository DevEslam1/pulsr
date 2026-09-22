// lib/features/settings/presentation/proxy_settings_screen.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/proxy_config.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';
import '../../../core/utils/input_sanitizer.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
part 'proxy_settings_sections.dart';

class ProxySettingsScreen extends StatefulWidget {
  final String? initialImportText;

  const ProxySettingsScreen({super.key, this.initialImportText});

  @override
  State<ProxySettingsScreen> createState() => _ProxySettingsScreenState();
}

class _ProxySettingsScreenState extends State<ProxySettingsScreen>
    with ProxySettingsSections {
  final _formKey = GlobalKey<FormState>();

  @override
  late bool _enabled;
  @override
  late AppProxyType _type;
  @override
  late TextEditingController _hostController;
  @override
  late TextEditingController _portController;
  @override
  late TextEditingController _usernameController;
  @override
  late TextEditingController _passwordController;
  @override
  late TextEditingController _bypassController;

  @override
  final FocusNode _hostFocusNode = FocusNode();
  @override
  final FocusNode _portFocusNode = FocusNode();
  @override
  final FocusNode _usernameFocusNode = FocusNode();
  @override
  final FocusNode _passwordFocusNode = FocusNode();
  @override
  final FocusNode _bypassFocusNode = FocusNode();

  @override
  bool _obscurePassword = true;
  bool _isTesting = false;
  @override
  ({bool success, int latencyMs, String? error})? _testResult;

  bool _loaded = false;

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

    _load();

    if (widget.initialImportText != null &&
        widget.initialImportText!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showImportDialog(prefilledText: widget.initialImportText);
        }
      });
    }
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final cubit = context.read<SettingsCubit>();
    try {
      final pw = await cubit.getProxyPassword();
      if (mounted && _passwordController.text.isEmpty && pw.isNotEmpty) {
        _passwordController.text = pw;
      }
    } catch (_) {
      // Ignore secure storage errors during initial load
    }
  }

  @override
  void dispose() {
    _hostFocusNode.dispose();
    _portFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _bypassFocusNode.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _bypassController.dispose();
    super.dispose();
  }

  void _syncControllersWithState(SettingsState state) {
    if (!_hostFocusNode.hasFocus && _hostController.text != state.proxyHost) {
      _hostController.text = state.proxyHost;
    }
    if (!_portFocusNode.hasFocus && _portController.text != state.proxyPort.toString()) {
      _portController.text = state.proxyPort.toString();
    }
    if (!_usernameFocusNode.hasFocus && _usernameController.text != state.proxyUsername) {
      _usernameController.text = state.proxyUsername;
    }
    if (!_bypassFocusNode.hasFocus && _bypassController.text != state.proxyBypassHosts) {
      _bypassController.text = state.proxyBypassHosts;
    }
    // Password lives in secure storage (not in SettingsState) — rehydrate it
    // so switching pool entries never leaves a stale password behind.
    if (!_passwordFocusNode.hasFocus) {
      context.read<SettingsCubit>().getProxyPassword().then((pw) {
        if (mounted && !_passwordFocusNode.hasFocus && _passwordController.text != pw) {
          _passwordController.text = pw;
        }
      });
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
              const SizedBox(width: AppSpacing.s10),
              Text(context.l10n.proxySaved),
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

  @override
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
        content: Text(context.l10n.proxyPresetApplied(name, host, port)),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
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

  @override
  Future<void> _showImportDialog({String? prefilledText}) async {
    final textController = TextEditingController(text: prefilledText ?? '');
    final p = context.palette;

    await PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: 20,
                    end: 20,
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
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              decoration: BoxDecoration(
                                color: p.accentContainer,
                                borderRadius: BorderRadius.circular(AppRadii.r10),
                              ),
                              child: Icon(Icons.file_upload_outlined,
                                  color: p.accent, size: 20),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(context.l10n.importProxies,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.title,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          tooltip: context.l10n.close,
                          icon:
                              Icon(Icons.close_rounded, color: p.textSecondary),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(context.l10n.pasteOrPick,
                      style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                    ),
                    const SizedBox(height: AppSpacing.sm),
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
                          label: Text(context.l10n.pasteClipboard,
                              style: TextStyle(
                                  color: p.textPrimary, fontSize: AppFontSize.label)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: p.hairline),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadii.r10)),
                            padding: const EdgeInsets.symmetric(

                                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final result = await FilePicker.pickFile(
                                type: FileType.custom,
                                allowedExtensions: [
                                  'txt',
                                  'csv',
                                  'list',
                                  'conf'
                                ],
                              );
                              if (result != null && result.path != null) {
                                final path = result.path!;
                                final file = File(path);
                                final content = await file.readAsString();
                                textController.text = content;
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(ctx.l10n
                                        .pickFileFailed(e.toString())),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                          icon: Icon(Icons.folder_open_rounded,
                              size: 16, color: p.accent),
                          label: Text(context.l10n.pickFile,
                              style: TextStyle(
                                  color: p.textPrimary, fontSize: AppFontSize.label)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: p.hairline),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadii.r10)),
                            padding: const EdgeInsets.symmetric(

                                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: textController,
                      maxLines: 6,
                      style: TextStyle(
                          color: p.textPrimary,
                          fontFamily: 'monospace',
                          fontSize: AppFontSize.label),
                      decoration: InputDecoration(
                        hintText:
                            '31.59.20.176:6754:username:password\n45.38.107.97:6014\nsocks5://user:pass@127.0.0.1:1080',
                        hintStyle: TextStyle(
                            color: p.textTertiary,
                            fontFamily: 'monospace',
                            fontSize: AppFontSize.label),
                        filled: true,
                        fillColor: p.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.r12),
                          borderSide: BorderSide(color: p.hairline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.r12),
                          borderSide: BorderSide(color: p.hairline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.r12),
                          borderSide: BorderSide(color: p.accent, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(context.l10n.cancel,
                              style: TextStyle(color: p.textSecondary)),
                        ),
                        const SizedBox(width: AppSpacing.xs),
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
                                      const SizedBox(width: AppSpacing.s10),
                                      Text(context.l10n
                                          .proxyImported(count)),
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
                                borderRadius: BorderRadius.circular(AppRadii.r12)),
                            padding: const EdgeInsets.symmetric(

                                horizontal: AppSpacing.md, vertical: AppSpacing.s10),
                          ),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: Text(context.l10n.importParse,
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
      listenWhen: (prev, curr) =>
          prev.proxyHost != curr.proxyHost ||
          prev.proxyPort != curr.proxyPort ||
          prev.proxyUsername != curr.proxyUsername ||
          prev.proxyBypassHosts != curr.proxyBypassHosts ||
          prev.proxyEnabled != curr.proxyEnabled ||
          prev.proxyType != curr.proxyType,
      listener: (context, state) {
        _syncControllersWithState(state);
      },
      builder: (context, state) {
        final proxyList = state.proxyList;
        final isTestingAll = state.isTestingAllProxies;

        return PulsrPagePopScope(
          child: Scaffold(
            backgroundColor: p.bg,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: const PulsrBackButton(),
              title: Text(
              context.l10n.proxySettings,
              style: TextStyle(
                color: p.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: AppFontSize.title,
              ),
            ),
            actions: [
              IconButton(
                tooltip: context.l10n.settingsImportPasteProxies,
                icon: Icon(Icons.file_upload_outlined, color: p.accent),
                onPressed: () => _showImportDialog(),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                child: FilledButton.tonalIcon(
                  onPressed: _saveSettings,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accentContainer,
                    foregroundColor: p.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r12),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.xs),
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
                      EdgeInsetsDirectional.fromSTEB(horizontalPad, AppSpacing.xs, horizontalPad, AppSpacing.xxl),
                  children: [
                    // Master Switch Card
                    _buildMasterToggle(p),
                    const SizedBox(height: AppSpacing.s20),

                    // Multi-Proxy Pool Section
                    _buildProxyPoolSection(p, state, proxyList, isTestingAll),
                    const SizedBox(height: AppSpacing.s20),

                    // Protocol Selection Card
                    _buildProtocolSection(p),
                    const SizedBox(height: AppSpacing.s20),

                    // Active Server Address & Port
                    _buildServerConfigSection(p),
                    const SizedBox(height: AppSpacing.s20),

                    // Authentication (Optional)
                    _buildAuthSection(p),
                    const SizedBox(height: AppSpacing.s20),

                    // Bypass Hosts
                    _buildBypassSection(p),
                    const SizedBox(height: AppSpacing.lg),

                    // Test Active Proxy Connection Button
                    FilledButton.icon(
                      onPressed: _isTesting ? null : _runTest,
                      icon: _isTesting
                          ? SizedBox(width: AppSpacing.s18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: p.onAccent,
                              ),
                            )
                          : const Icon(Icons.speed_rounded),
                      label: Text(
                        _isTesting
                            ? context.l10n.settingsTestingProxyConnectivity
                            : context.l10n.testProxy,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.r14),
                        ),
                      ),
                    ),

                    if (_testResult != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _buildTestResultCard(p, _testResult!),
                    ],
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

  Widget _buildMasterToggle(PulsrPalette p) {
    return Container(
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.r20),
        border: Border.all(
          color: _enabled ? p.accent.withValues(alpha: 0.4) : p.hairline,
          width: _enabled ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _enabled ? p.accentContainer : p.surface,
                  borderRadius: BorderRadius.circular(AppRadii.r12),
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
              const SizedBox(width: AppSpacing.s14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(context.l10n.enableProxy,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: AppFontSize.callout,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(

                              horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
                          decoration: BoxDecoration(
                            color: _enabled
                                ? p.success.withValues(alpha: 0.15)
                                : p.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(AppRadii.r6),
                          ),
                          child: Text(
                            _enabled ? context.l10n.settingsActiveBadge : context.l10n.settingsDisabledBadge,
                            style: TextStyle(
                              color: _enabled ? p.success : p.textTertiary,
                              fontSize: AppFontSize.micro,
                              fontWeight: FontWeight.w800,
                              letterSpacing: AppTracking.medium,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _enabled
                          ? context.l10n.settingsProxyActiveDesc
                          : context.l10n.settingsProxyInactiveDesc,
                      style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
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


  @override
  Widget _buildSection({
    required PulsrPalette p,
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s6, 0, 0, AppSpacing.xs),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: p.textTertiary,
                  letterSpacing: AppTracking.medium,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Material(
          color: p.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.r20),
            side: BorderSide(color: p.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }

  @override
  Widget _presetChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required PulsrPalette p,
  }) {
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.r10),
        side: BorderSide(color: p.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: p.accent),
              const SizedBox(width: AppSpacing.s6),
              Text(
                label,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.label,
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.r16),
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
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSuccess ? context.l10n.settingsConnectionSuccessful : context.l10n.settingsConnectionFailed,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.body,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  isSuccess
                      ? context.l10n.settingsLatencyMs(result.latencyMs)
                      : (result.error ?? context.l10n.settingsUnknownConnectionFailure),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.label,
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
