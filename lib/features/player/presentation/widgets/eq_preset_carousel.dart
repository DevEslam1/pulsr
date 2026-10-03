part of 'equalizer_sheet.dart';

extension _EqPresetCarousel on _EqualizerSheetState {
  Future<void> _resetAllDspDefaults(
      BuildContext context, PlayerCubit cubit) async {
    await cubit.resetToFlat();
    await cubit.setBassBoost(0.0);
    await cubit.setVolumeBoost(0.0);
    await cubit.setVirtualizerEnabled(false);
    await cubit.setVirtualizerStrength(0.0);
    await cubit.setDynamicsPreset(DynamicsPreset.off);
    await cubit.setCrossfeed(false, delayUs: 350.0, feedDb: -9.0);
    await cubit.setLookaheadLimiter(false, thresholdDb: -0.2, releaseMs: 50.0);
    await cubit.setStereoBalance(0.0);
    await cubit.setReverb(false, preset: 0, wetDry: 0.20);
    await cubit.setSaturation(false, drive: 0.3, mix: 0.5, tilt: 0.3);
    await cubit.setStereoWidth(false, width: 1.0);
    await cubit.setSubCrossover(false, cornerHz: 80.0, gain: 0.8);
    await cubit.setDynamicEq(false);
    await cubit.setLoudnessContour(false, intensity: 0.0);
    HapticFeedback.mediumImpact();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(context.l10n.eqResetNotice),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showSaveCustomPresetDialog(
      PlayerCubit cubit, PlayerState state) async {
    final name = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.saveCustomEqPreset,
      initialText: context.l10n.dspMyCustomEq,
      hintText: context.l10n.dspPresetNameHint,
      icon: Icons.equalizer_rounded,
      confirmLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
    );
    if (name != null && name.trim().isNotEmpty) {
      final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      // Read from the cubit at tap time: with the F-10 gating, this build's
      // captured `state` may predate the latest band-drag gains.
      final currentEq = cubit.state.eqPreset;
      final profile = HeadphoneProfile(
        id: id,
        name: name,
        brand: 'User Custom',
        model: name,
        category: 'Custom',
        gains: List<double>.from(currentEq.gains),
        bassBoost: currentEq.bassBoost,
      );
      await _headphoneRepo.addCustomProfile(profile);
      await cubit.applyHeadphoneProfile(profile);
      if (mounted) {
        _setStateSafe(() {});
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.eqPresetSaved(name))),
        );
      }
    }
  }

  Future<void> _exportCurrentPreset(
      BuildContext context, PlayerCubit cubit) async {
    try {
      final jsonString = cubit.exportCurrentEqPreset();
      await SharePlus.instance.share(
        ShareParams(
          text: jsonString,
          subject: 'Pulsr EQ Preset - ${cubit.state.eqPreset.name}',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.exportFailed)),
        );
      }
    }
  }

  Future<void> _importPresetDialog(
      BuildContext context, PlayerCubit cubit) async {
    final textController = TextEditingController();
    final jsonString = await PulsrDialogHelper.showCustomDialog<String>(
      context,
      builder: (ctx) => PulsrDialog(
        title: context.l10n.importEqPreset,
        icon: Icons.file_download_rounded,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.pasteJsonPreset,
              style: TextStyle(
                  fontSize: AppFontSize.bodySmall,
                  color: context.palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s10),
            TextField(
              controller: textController,
              autofocus: true,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '{"name": "...", "gains": [...]}',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: Text(context.l10n.importAction),
          ),
        ],
      ),
    );

    // The dialog has closed; release the controller (previously leaked on every
    // import).
    textController.dispose();

    if (jsonString != null && jsonString.isNotEmpty) {
      final success = await cubit.importEqPreset(jsonString);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(success
                ? context.l10n.dspPresetImported
                : context.l10n.dspPresetImportInvalid),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// F-32: edit the active band plan's center frequencies. Validates strictly
  /// ascending order and a sane 10 Hz..30 kHz range before applying, then
  /// re-pushes to the engine (the center-frequency setters only persist).
  Future<void> _showCustomFrequencyEditor(
      PlayerCubit cubit, PlayerState state) async {
    final bandCount = _activeBandCount(state);
    final initial = List<double>.from(_activeFrequencies(state));
    final controllers = [
      for (final f in initial)
        TextEditingController(
            text: f == f.roundToDouble()
                ? f.toStringAsFixed(0)
                : f.toStringAsFixed(1)),
    ];
    try {
      String? error;
      final applied = await PulsrDialogHelper.showCustomDialog<bool>(
        context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => PulsrDialog(
            title: context.l10n.customBandFreqs(initial.length),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.centerFreqHelp,
                    style: const TextStyle(fontSize: AppFontSize.label),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(error!,
                        style: TextStyle(
                            color: context.palette.error,
                            fontSize: AppFontSize.label)),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (var i = 0; i < controllers.length; i++)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.xxs),
                              child: TextField(
                                // Mi-4: Stable key preserves focus + text on
                                // dialog re-renders triggered by error state.
                                key: ValueKey('eq_freq_field_$i'),
                                controller: controllers[i],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: context.l10n.eqBandLabel(i + 1),
                                  suffixText: 'Hz',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = <double>[];
                  for (final c in controllers) {
                    final v = double.tryParse(c.text.trim());
                    if (v == null) {
                      setDialogState(
                          () => error = context.l10n.dspEveryBandValidNumber);
                      return;
                    }
                    parsed.add(v);
                  }
                  for (var i = 0; i < parsed.length; i++) {
                    if (parsed[i] < 10 || parsed[i] > 30000) {
                      setDialogState(
                          () => error = context.l10n.dspFreqRange10To30k);
                      return;
                    }
                    if (i > 0 && parsed[i] <= parsed[i - 1]) {
                      setDialogState(
                          () => error = context.l10n.dspFreqStrictlyAscending);
                      return;
                    }
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(context.l10n.apply),
              ),
            ],
          ),
        ),
      );

      if (applied == true) {
        final parsed = [
          for (final c in controllers) double.parse(c.text.trim()),
        ];
        final manager = _equalizerManagerOrNull();
        if (manager != null) {
          if (bandCount == 64) {
            await manager.setCustom64Frequencies(parsed);
          } else if (bandCount == 32) {
            await manager.setCustom32Frequencies(parsed);
          } else {
            await manager.setCustomFrequencies(parsed);
          }
        }
        // The center-frequency setters only persist; re-push the active plan so
        // the native parametric EQ picks up the new centers immediately.
        _mutedBands.clear();
        _soloedBands.clear();
        await cubit.setBandMode(bandCount);
        if (mounted) {
          _setStateSafe(() {});
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(context.l10n.customFreqsApplied),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      for (final c in controllers) {
        c.dispose();
      }
    }
  }

  /// F-37: room-correction entry surfaced from the EQ sheet. Opens the
  /// measurement wizard or exports the current curve to the convolution stage
  /// as a linear-phase FIR (see [PlayerCubit.exportCorrectionImpulseResponse]).
  Future<void> _showRoomCorrectionActions(PlayerCubit cubit) async {
    final action = await PulsrDialogHelper.showCustomDialog<String>(
      context,
      builder: (ctx) => PulsrDialog(
        title: context.l10n.roomCorrection,
        icon: Icons.mic_rounded,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.roomMeasureHelp,
              style: const TextStyle(fontSize: AppFontSize.label),
            ),
            const SizedBox(height: AppSpacing.xs),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mic_rounded),
              title: Text(context.l10n.measureRoom),
              subtitle: Text(context.l10n.roomWizardDesc),
              onTap: () => Navigator.pop(ctx, 'measure'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune_rounded),
              title: Text(context.l10n.exportEqFir),
              subtitle: Text(context.l10n.firDesc),
              onTap: () => Navigator.pop(ctx, 'export'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'measure') {
      await RoomCorrectionSheet.show(context);
    } else if (action == 'export') {
      await _exportCurrentCurveAsFir(cubit, cubit.state);
    }
  }

  Future<void> _exportCurrentCurveAsFir(
      PlayerCubit cubit, PlayerState state) async {
    final gains = List<double>.from(state.eqPreset.gains);
    final centers = _activeFrequencies(state);
    final ir = cubit.exportCorrectionImpulseResponse(
      gains,
      centers: centers.length == gains.length ? centers : null,
    );
    final loaded = await cubit.loadCustomImpulseResponse(ir);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
            loaded ? context.l10n.dspFirLoaded : context.l10n.dspFirRejected),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
