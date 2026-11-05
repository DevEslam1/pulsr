part of 'audio_sound_section.dart';

/// DAC voicing selector (opt-in reconstruction-filter character plus an
/// even-order harmonic tail).
///
/// Persisted through [DacVoicingService] rather than settings state, so no
/// codegen is required — the same choice the DoP container selector makes. The
/// service owns the preference and the native push; this widget only mirrors it
/// locally so the controls respond immediately.
///
/// Off is a bit-exact passthrough in the engine, which is why the default is
/// off: the stage adds latency when enabled and reports it like the other
/// delaying stages.
class _DacVoicingSelector extends StatefulWidget {
  const _DacVoicingSelector();

  @override
  State<_DacVoicingSelector> createState() => _DacVoicingSelectorState();
}

class _DacVoicingSelectorState extends State<_DacVoicingSelector> {
  bool _loaded = false;
  bool _enabled = false;
  DacVoicingCharacter _character = DacVoicingCharacter.sharp;
  double _amount = 0;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final service = DacVoicingService.instance;
    // Playback startup normally loads this; opening settings first must not
    // show defaults for a preference the user already saved.
    if (!service.loaded) await service.load();
    if (!mounted) return;
    setState(() {
      _enabled = service.enabled;
      _character = service.character;
      _amount = service.amount;
      _loaded = true;
    });
  }

  Future<void> _setChanged({
    bool? enabled,
    DacVoicingCharacter? character,
    double? amount,
  }) async {
    final service = DacVoicingService.instance;
    setState(() {
      if (enabled != null) _enabled = enabled;
      if (character != null) _character = character;
      if (amount != null) _amount = amount;
    });
    if (enabled != null) await service.setEnabled(enabled);
    if (character != null) await service.setCharacter(character);
    if (amount != null) await service.setAmount(amount);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSwitchTile(
          Icons.memory_rounded,
          context.l10n.settingsDacVoicing,
          context.l10n.settingsDacVoicingDesc,
          value: _enabled,
          onChanged: (v) => _setChanged(enabled: v),
        ),
        if (_enabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<DacVoicingCharacter>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: AppSpacing.xxs)),
                ),
                segments: [
                  ButtonSegment(
                    value: DacVoicingCharacter.sharp,
                    label: Text(
                      context.l10n.settingsDacVoicingSharp,
                      style: const TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ButtonSegment(
                    value: DacVoicingCharacter.slow,
                    label: Text(
                      context.l10n.settingsDacVoicingSlow,
                      style: const TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ButtonSegment(
                    value: DacVoicingCharacter.minimumPhase,
                    label: Text(
                      context.l10n.settingsDacVoicingMinPhase,
                      style: const TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                selected: {_character},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    _setChanged(character: selected.first);
                  }
                },
              ),
            ),
          ),
          SettingSliderRow(
            label: context.l10n.settingsDacVoicingAmount,
            subtitle: context.l10n.settingsDacVoicingAmountDesc,
            value: _amount * 100,
            min: 0,
            max: 100,
            divisions: 20,
            defaultValue: 0,
            formatValue: (v) => '${v.round()} %',
            enabled: _enabled,
            onChanged: (v) => _setChanged(amount: v / 100.0),
          ),
        ],
      ],
    );
  }
}
