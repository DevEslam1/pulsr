// ignore_for_file: unused_element_parameter
part of 'proxy_settings_screen.dart';

mixin ProxySettingsSections on State<ProxySettingsScreen> {
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
                  Text(context.l10n.savedProxyPool,
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
                    final confirm = await PulsrDialogHelper.showConfirmDialog(
                      context,
                      title: context.l10n.clearPoolTitle,
                      message: context.l10n.clearPoolConfirm(proxyList.length),
                      icon: Icons.delete_sweep_rounded,
                      confirmLabel: context.l10n.clearAll,
                      cancelLabel: context.l10n.cancel,
                      isDestructive: true,
                    );
                    if (confirm == true && mounted) {
                      context.read<SettingsCubit>().clearProxyList();
                    }
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(context.l10n.clearAll,
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
                      label: Text(context.l10n.importPaste,
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
                          isTestingAll ? context.l10n.settingsTestingAll : context.l10n.settingsTestAllSpeeds,
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
                        label: Text(context.l10n.sortBySpeed,
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
                        Text(context.l10n.noProxiesPool,
                          style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Text(context.l10n.importProxiesDesc,
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
              content: Text(context.l10n.proxyActivated(item.displayAddress)),
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
                            child: Text(context.l10n.activeLabel,
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
                      tooltip: context.l10n.settingsTestLatency,
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
                      tooltip: context.l10n.settingsRemoveProxy,
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
                        item.type == AppProxyType.socks5 ? context.l10n.socks5 : context.l10n.settingsHttpLabel,
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
            Text(context.l10n.testingLabel,
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
          : (latency < 6000 ? p.warning : p.error);

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
            Text(context.l10n.failedLabel,
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
      child: Text(context.l10n.unverifiedLabel,
        style: TextStyle(
            color: p.textTertiary, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildProtocolSection(PulsrPalette p) {
    return _buildSection(
      p: p,
      title: context.l10n.settingsActiveProxyProtocol,
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
                segments: [
                  ButtonSegment(
                    value: AppProxyType.http,
                    label: Text(context.l10n.httpHttps,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    icon: Icon(Icons.http_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: AppProxyType.socks5,
                    label: Text(context.l10n.socks5,
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
                        ? context.l10n.settingsProxyHttpDesc
                        : context.l10n.settingsProxySocksDesc,
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
      title: context.l10n.settingsActiveServerConfig,
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
                    labelText: context.l10n.settingsServerHost,
                    hintText: context.l10n.settingsServerHostHint,
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
                      return context.l10n.settingsEnterProxyHost;
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
                    labelText: context.l10n.settingsPortLabel,
                    hintText: context.l10n.settingsPortHint,
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
                        return context.l10n.settingsInvalidPort;
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
            Text(context.l10n.quickPresets,
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
      title: context.l10n.settingsAuthenticationOptional,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 480;

            final usernameField = TextFormField(
              controller: _usernameController,
              style: TextStyle(color: p.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: context.l10n.settingsUsernameLabel,
                hintText: context.l10n.settingsLeaveBlankAuth,
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
                labelText: context.l10n.settingsPasswordLabel,
                hintText: context.l10n.settingsLeaveBlankAuth,
                labelStyle: TextStyle(color: p.textSecondary),
                hintStyle: TextStyle(color: p.textTertiary),
                prefixIcon:
                    Icon(Icons.lock_outline_rounded, color: p.accent, size: 20),
                suffixIcon: IconButton(
                  tooltip: context.l10n.settingsPasswordLabel,
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
      title: context.l10n.proxyBypass,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _bypassController,
              style: TextStyle(color: p.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: context.l10n.settingsBypassList,
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
                  child: Text(context.l10n.bypassHostsDesc,
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



















































































  // Requires: provided by the composing class (same library).
  void _appendBypassHost(String host);

  // Requires: provided by the composing class (same library).
  void _applyPreset({ required String name, required AppProxyType type, required String host, required int port, });

  // Requires: provided by the composing class (same library).
  Widget _buildSection({ required PulsrPalette p, required String title, required Widget child, });

  // Requires: provided by the composing class (same library).
  TextEditingController get _bypassController;

  // Requires: provided by the composing class (same library).
  bool get _enabled;

  // Requires: provided by the composing class (same library).
  TextEditingController get _hostController;

  // Requires: provided by the composing class (same library).
  bool get _obscurePassword;
  set _obscurePassword(bool value);

  // Requires: provided by the composing class (same library).
  TextEditingController get _passwordController;

  // Requires: provided by the composing class (same library).
  TextEditingController get _portController;

  // Requires: provided by the composing class (same library).
  Widget _presetChip({ required String label, required IconData icon, required VoidCallback onTap, required PulsrPalette p, });

  // Requires: provided by the composing class (same library).
  Future<void> _showImportDialog({String? prefilledText});

  // Requires: provided by the composing class (same library).
  // ignore: unused_element
  ({bool success, int latencyMs, String? error})? get _testResult;
  set _testResult(({bool success, int latencyMs, String? error})? value);

  // Requires: provided by the composing class (same library).
  AppProxyType get _type;
  set _type(AppProxyType value);

  // Requires: provided by the composing class (same library).
  TextEditingController get _usernameController;
}
