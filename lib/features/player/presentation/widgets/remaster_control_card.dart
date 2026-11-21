part of 'equalizer_sheet.dart';

class RemasterControlCard extends StatefulWidget {
  /// Non-null when bit-perfect playback currently bypasses the DSP chain.
  final String? blockedReason;

  /// False when no native PCM effect chain is loaded on this platform.
  final bool nativeAvailable;

  const RemasterControlCard({
    super.key,
    this.blockedReason,
    this.nativeAvailable = true,
  });

  @override
  State<RemasterControlCard> createState() => _RemasterControlCardState();
}

class _RemasterControlCardState extends State<RemasterControlCard> {
  static const TextStyle _labelStyle = TextStyle(
    fontSize: AppFontSize.caption,
    fontWeight: FontWeight.w700,
  );

  int _multiplier = 1;
  int _kernel = 0;
  bool _pcmToDsdEnabled = false;
  int _pcmToDsdRate = 64;
  int _pcmToDsdOrder = 5;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final storedMult =
        prefs.getInt(PrefsKeys.remasterOversampleMultiplier) ?? 1;
    final storedKernel = prefs.getInt(PrefsKeys.remasterFilterKernel) ?? 0;
    final storedDsdEnabled =
        prefs.getBool(PrefsKeys.remasterPcmToDsdEnabled) ?? false;
    final storedDsdRate = prefs.getInt(PrefsKeys.remasterPcmToDsdRate) ?? 64;
    final storedDsdOrder = prefs.getInt(PrefsKeys.remasterPcmToDsdOrder) ?? 5;

    setState(() {
      _multiplier =
          (storedMult == 2 || storedMult == 4 || storedMult == 8)
              ? storedMult
              : 1;
      _kernel = storedKernel.clamp(0, 3);
      _pcmToDsdEnabled = storedDsdEnabled;
      _pcmToDsdRate =
          (storedDsdRate == 128 || storedDsdRate == 256) ? storedDsdRate : 64;
      _pcmToDsdOrder = storedDsdOrder.clamp(1, 5);
      _loaded = true;
    });

    if (widget.blockedReason == null && widget.nativeAvailable) {
      try {
        await AudioEffectsChannel().setOversampleMultiplier(_multiplier);
        await AudioEffectsChannel().setOversampleKernel(_kernel);
        await AudioEffectsChannel().setPcmToDsdEnabled(_pcmToDsdEnabled);
        await AudioEffectsChannel().setPcmToDsdRate(_pcmToDsdRate);
        await AudioEffectsChannel().setPcmToDsdOrder(_pcmToDsdOrder);
      } catch (e, st) {
        ErrorLogger.log('Failed to restore native remaster settings',
            error: e, stackTrace: st, category: 'Remaster');
      }
    }
  }

  Future<void> _selectMultiplier(int multiplier) async {
    if (multiplier == _multiplier) return;
    PulsrHaptics.selectionClick();
    final previous = _multiplier;
    setState(() => _multiplier = multiplier);
    try {
      final applied =
          await AudioEffectsChannel().setOversampleMultiplier(multiplier);
      if (!applied && multiplier != 1) {
        throw StateError('oversampling multiplier refused');
      }
    } catch (_) {
      if (mounted) setState(() => _multiplier = previous);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await prefs.setInt(PrefsKeys.remasterOversampleMultiplier, multiplier);
    if (getIt.isRegistered<SettingsCubit>()) {
      // Force: the target may be unchanged (e.g. 2x -> 2x after a refused DAC
      // rate) but the sink still has to rebuild before status may claim it.
      unawaited(getIt<SettingsCubit>().syncTapSrcRate(force: true));
    }
  }

  Future<void> _selectKernel(int kernel) async {
    if (kernel == _kernel) return;
    PulsrHaptics.selectionClick();
    final previous = _kernel;
    setState(() => _kernel = kernel);
    try {
      final applied = await AudioEffectsChannel().setOversampleKernel(kernel);
      if (!applied) throw StateError('reconstruction kernel refused');
    } catch (_) {
      if (mounted) setState(() => _kernel = previous);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await prefs.setInt(PrefsKeys.remasterFilterKernel, kernel);
    if (_multiplier > 1 && getIt.isRegistered<SettingsCubit>()) {
      // Kernel coefficients are rebuilt by the control thread when the sink
      // reopens; never from the audio callback.
      unawaited(getIt<SettingsCubit>().syncTapSrcRate(force: true));
    }
  }

  Future<void> _togglePcmToDsd(bool enabled) async {
    if (enabled == _pcmToDsdEnabled) return;
    PulsrHaptics.selectionClick();
    final previous = _pcmToDsdEnabled;
    setState(() => _pcmToDsdEnabled = enabled);
    try {
      final applied = await AudioEffectsChannel().setPcmToDsdEnabled(enabled);
      if (!applied && enabled) throw StateError('PCM->DSD toggle refused');
    } catch (_) {
      if (mounted) setState(() => _pcmToDsdEnabled = previous);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await prefs.setBool(PrefsKeys.remasterPcmToDsdEnabled, enabled);
  }

  Future<void> _selectDsdRate(int rate) async {
    if (rate == _pcmToDsdRate) return;
    PulsrHaptics.selectionClick();
    final previous = _pcmToDsdRate;
    setState(() => _pcmToDsdRate = rate);
    try {
      final applied = await AudioEffectsChannel().setPcmToDsdRate(rate);
      if (!applied) throw StateError('DSD rate refused');
    } catch (_) {
      if (mounted) setState(() => _pcmToDsdRate = previous);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await prefs.setInt(PrefsKeys.remasterPcmToDsdRate, rate);
  }

  Future<void> _selectDsdOrder(int order) async {
    if (order == _pcmToDsdOrder) return;
    PulsrHaptics.selectionClick();
    final previous = _pcmToDsdOrder;
    setState(() => _pcmToDsdOrder = order);
    try {
      final applied = await AudioEffectsChannel().setPcmToDsdOrder(order);
      if (!applied) throw StateError('DSD order refused');
    } catch (_) {
      if (mounted) setState(() => _pcmToDsdOrder = previous);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await prefs.setInt(PrefsKeys.remasterPcmToDsdOrder, order);
  }

  static String _kernelLabel(int kernel) {
    switch (kernel) {
      case 0:
        return 'Sharp';
      case 1:
        return 'Slow Roll-off';
      case 2:
        return 'MinPhase';
      case 3:
      default:
        return 'Apodizing';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled =
        widget.blockedReason == null && widget.nativeAvailable && _loaded;
    final isRemasterActive = _multiplier > 1 || _pcmToDsdEnabled;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  borderRadius: AppRadii.r8All,
                ),
                child:
                    Icon(Icons.auto_fix_high_rounded, color: p.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remaster Suite',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.body,
                          color: p.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Output oversampling, reconstruction filters & PCM→DSD',
                      style: TextStyle(
                          fontSize: AppFontSize.caption, color: p.textTertiary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),

          // Output Oversampling Multiplier
          Text(
            'PCM Output Oversampling',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppFontSize.caption,
                color: p.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                ),
              ),
              segments: const [
                ButtonSegment(
                  value: 1,
                  label: Text('Off (1x)', style: _labelStyle),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('2x', style: _labelStyle),
                ),
                ButtonSegment(
                  value: 4,
                  label: Text('4x', style: _labelStyle),
                ),
                ButtonSegment(
                  value: 8,
                  label: Text('8x', style: _labelStyle),
                ),
              ],
              selected: {_multiplier},
              onSelectionChanged: enabled
                  ? (values) {
                      if (values.isNotEmpty) _selectMultiplier(values.first);
                    }
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),

          // Reconstruction Filter Kernel
          Text(
            'Reconstruction Filter Kernel',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppFontSize.caption,
                color: p.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                ),
              ),
              segments: [
                for (var i = 0; i < 4; i++)
                  ButtonSegment(
                    value: i,
                    label: Text(_kernelLabel(i), style: _labelStyle),
                  ),
              ],
              selected: {_kernel},
              onSelectionChanged: enabled
                  ? (values) {
                      if (values.isNotEmpty) _selectKernel(values.first);
                    }
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),

          // PCM -> DSD Sigma-Delta Modulator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PCM → DSD Modulator',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: AppFontSize.caption,
                        color: p.textSecondary),
                  ),
                  Text(
                    'Offline SDM engine (no playback route yet)',
                    style: TextStyle(
                        fontSize: AppFontSize.caption - 1,
                        color: p.textTertiary),
                  ),
                ],
              ),
              Switch.adaptive(
                value: _pcmToDsdEnabled,
                onChanged: enabled ? _togglePcmToDsd : null,
              ),
            ],
          ),
          if (_pcmToDsdEnabled) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DSD Rate',
                        style: TextStyle(
                            fontSize: AppFontSize.caption - 1,
                            color: p.textTertiary,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: 64,
                            label: Text('DSD64', style: _labelStyle),
                          ),
                          ButtonSegment(
                            value: 128,
                            label: Text('128', style: _labelStyle),
                          ),
                          ButtonSegment(
                            value: 256,
                            label: Text('256', style: _labelStyle),
                          ),
                        ],
                        selected: {_pcmToDsdRate},
                        onSelectionChanged: enabled
                            ? (values) {
                                if (values.isNotEmpty) {
                                  _selectDsdRate(values.first);
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SDM Order (1-5)',
                        style: TextStyle(
                            fontSize: AppFontSize.caption - 1,
                            color: p.textTertiary,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: 1,
                            label: Text('1', style: _labelStyle),
                          ),
                          ButtonSegment(
                            value: 3,
                            label: Text('3', style: _labelStyle),
                          ),
                          ButtonSegment(
                            value: 5,
                            label: Text('5', style: _labelStyle),
                          ),
                        ],
                        selected: {_pcmToDsdOrder == 1 ? 1 : (_pcmToDsdOrder <= 3 ? 3 : 5)},
                        onSelectionChanged: enabled
                            ? (values) {
                                if (values.isNotEmpty) {
                                  _selectDsdOrder(values.first);
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.s10),

          // Bit-Perfect State Indicator
          if (isRemasterActive)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
              decoration: BoxDecoration(
                color: p.warning.withValues(alpha: 0.15),
                borderRadius: AppRadii.r6All,
                border: Border.all(color: p.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: p.warning),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      _pcmToDsdEnabled
                          ? 'PCM → DSD requested · offline engine only, not on the playback route'
                          : 'Oversampling ${_multiplier}x requested · Not Bit-Perfect (reconstruction DSP in path)',
                      style: TextStyle(
                        color: p.warning,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
              decoration: BoxDecoration(
                color: p.success.withValues(alpha: 0.12),
                borderRadius: AppRadii.r6All,
                border: Border.all(color: p.success.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      size: 14, color: p.success),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Bit-Perfect compatible (passthrough)',
                      style: TextStyle(
                        color: p.success,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (widget.blockedReason != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(context.l10n.blockedByBitPerfectShort,
                  style: TextStyle(
                      color: p.error,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600)),
            )
          else if (!widget.nativeAvailable)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(context.l10n.nativeDspUnavailable,
                  style: TextStyle(
                      color: p.textTertiary,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
