import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/services/ambient_sound_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_switch.dart';

import '../../../../core/utils/pulsr_haptics.dart';
/// Icon for each ambient effect.
IconData iconForEffect(AmbientSoundEffect effect) {
  switch (effect) {
    case AmbientSoundEffect.rain:
      return Icons.water_drop_rounded;
    case AmbientSoundEffect.fire:
      return Icons.local_fire_department_rounded;
    case AmbientSoundEffect.forest:
      return Icons.park_rounded;
    case AmbientSoundEffect.ocean:
      return Icons.waves_rounded;
    case AmbientSoundEffect.wind:
      return Icons.air_rounded;
    case AmbientSoundEffect.thunder:
      return Icons.thunderstorm_rounded;
    case AmbientSoundEffect.birds:
      return Icons.flutter_dash_rounded;
    case AmbientSoundEffect.cafe:
      return Icons.coffee_rounded;
    case AmbientSoundEffect.whiteNoise:
      return Icons.graphic_eq_rounded;
  }
}

/// Multi-effect Ambient Sound control panel.
///
/// Displays selectable effect chips with individual volume sliders.
/// Multiple effects can be enabled simultaneously. Automatically pauses
/// when the main player pauses and resumes when it plays again.
class AmbientSoundPanel extends StatefulWidget {
  final EdgeInsetsGeometry? padding;
  final bool showContainerDecoration;
  final bool showHeader;

  const AmbientSoundPanel({
    super.key,
    this.padding,
    this.showContainerDecoration = true,
    this.showHeader = true,
  });

  @override
  State<AmbientSoundPanel> createState() => _AmbientSoundPanelState();
}

class _AmbientSoundPanelState extends State<AmbientSoundPanel> {
  final AmbientSoundService _service = AmbientSoundService();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    unawaited(_service.init());
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  bool _isTimerChoice(int? minutes) {
    final remaining = _service.sleepTimeRemaining;
    if (minutes == null) return remaining == null;
    if (remaining == null) return false;
    // Selected chip = smallest preset that still covers the remaining time.
    const presets = [15, 30, 60, 120];
    final chosen = presets.firstWhere(
      (m) => remaining <= Duration(minutes: m),
      orElse: () => presets.last,
    );
    return chosen == minutes;
  }

  String _formatRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _sectionLabel(String text, dynamic p) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: p.textSecondary,
          fontSize: AppFontSize.caption,
          fontWeight: FontWeight.w800,
          letterSpacing: AppTracking.overline,
        ),
      );

  Future<void> _promptSaveMix() async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.ambientSaveMix),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.ambientMixName),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.ambientCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.ambientSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) _service.saveMix(name);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header ────────────────────────────────────────────────────────────
        if (widget.showHeader) ...[
          Row(
            children: [
              Icon(
                _service.isEnabled
                    ? Icons.water_drop_rounded
                    : Icons.water_drop_outlined,
                color: _service.isEnabled ? p.accent : p.textSecondary,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          context.l10n.ambientSounds,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.body,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_service.isEnabled) ...[
                          const SizedBox(width: AppSpacing.xs),
                          _StatusBadge(
                            isPlaying: _service.isAudioPlaying,
                            palette: p,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _ActiveBadge(
                            count: _service.activeEffects.length,
                            palette: p,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      _service.isEnabled && _service.isSuppressedByQuran
                          ? context.l10n.ambientAllowDuringQuran
                          : _service.isEnabled && !_service.isPlayerPlaying
                              ? context.l10n.ambientPausedWithPlayer
                              : _service.isEnabled
                                  ? _service.activeEffects
                                      .map((e) => e.emoji)
                                      .join(' ')
                                  : context.l10n.ambientSoundsDesc,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.label,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: context.l10n.ambientSounds,
                toggled: _service.isEnabled,
                value: _service.isEnabled
                    ? context.l10n.semanticsStateOn
                    : context.l10n.semanticsStateOff,
                child: PulsrSwitch(
                  value: _service.isEnabled,
                  onChanged: (v) {
                    PulsrHaptics.selectionClick();
                    unawaited(_service.setEnabled(v));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: AppSpacing.s10),
        ],

        // ── Error ─────────────────────────────────────────────────────────────
        if (_service.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _service.errorMessage!,
            style: TextStyle(color: p.error, fontSize: AppFontSize.label),
          ),
        ],

        // ── Effect chips ──────────────────────────────────────────────────────
        Text(
          context.l10n.ambientEffectsHeader.toUpperCase(),
          style: TextStyle(
            color: p.textSecondary,
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w800,
            letterSpacing: AppTracking.overline,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: AmbientSoundEffect.values.map((effect) {
            final selected = _service.isEffectActive(effect);
            return Semantics(
              label: effect.localizedDisplayName(context.l10n),
              selected: selected,
              child: ChoiceChip(
                selected: selected,
                onSelected: (_) {
                  PulsrHaptics.selectionClick();
                  unawaited(_service.toggleEffect(effect));
                },
                avatar: Text(
                  effect.emoji,
                  style: const TextStyle(fontSize: 16),
                ),
                label: Text(effect.localizedLabel(context.l10n)),
                labelStyle: TextStyle(
                  color: selected ? p.onAccent : p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.label,
                ),
                backgroundColor: p.surfaceContainer,
                selectedColor: p.accent,
                side: BorderSide(
                  color: selected ? p.accent : p.hairline,
                ),
                showCheckmark: false,
              ),
            );
          }).toList(),
        ),

        // ── Per-effect volume sliders (shown only for active effects) ──────────
        if (_service.isEnabled) ...[
          const SizedBox(height: AppSpacing.s14),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: AppSpacing.s10),
          Text(
            context.l10n.ambientVolumesHeader.toUpperCase(),
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w800,
              letterSpacing: AppTracking.overline,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...AmbientSoundEffect.values
              .where(_service.isEffectActive)
              .map((effect) => _VolumeRow(
                    effect: effect,
                    volume: _service.volumeFor(effect),
                    palette: p,
                    onChanged: (v) => _service.setEffectVolume(effect, v),
                  )),
          _MasterVolumeRow(
            label: context.l10n.ambientMasterVolume,
            volume: _service.masterVolume,
            palette: p,
            onChanged: _service.setMasterVolume,
          ),
        ],

        // ── Sleep timer ───────────────────────────────────────────────────────
        if (_service.isEnabled) ...[
          const SizedBox(height: AppSpacing.s10),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: AppSpacing.s10),
          _sectionLabel(context.l10n.ambientSleepTimer, p),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final minutes in const [null, 15, 30, 60, 120])
                ChoiceChip(
                  selected: _isTimerChoice(minutes),
                  showCheckmark: false,
                  label: Text(minutes == null
                      ? context.l10n.ambientSleepTimerOff
                      : context.l10n.ambientSleepTimerMinutes(minutes)),
                  onSelected: (_) {
                    PulsrHaptics.selectionClick();
                    _service.setSleepTimer(
                        minutes == null ? null : Duration(minutes: minutes));
                  },
                ),
            ],
          ),
          if (_service.sleepTimeRemaining != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _formatRemaining(_service.sleepTimeRemaining!),
                style: TextStyle(
                  color: p.accent,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],

        // ── Saved mixes ───────────────────────────────────────────────────────
        if (_service.isEnabled || _service.savedMixes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s10),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: AppSpacing.s10),
          Row(
            children: [
              Expanded(
                child: _sectionLabel(context.l10n.ambientSavedMixes, p),
              ),
              if (_service.isEnabled)
                TextButton.icon(
                  onPressed: _promptSaveMix,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: Text(context.l10n.ambientSaveMix),
                ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final name in _service.savedMixes.keys)
                InputChip(
                  label: Text(name),
                  onPressed: () => unawaited(_service.applyMix(name)),
                  onDeleted: () => _service.deleteMix(name),
                ),
            ],
          ),
        ],

        // ── Options (Quran mode behaviour) ────────────────────────────────────
        const SizedBox(height: AppSpacing.s10),
        Divider(height: 1, color: p.hairline),
        const SizedBox(height: AppSpacing.s10),
        Row(
          children: [
            Icon(
              Icons.auto_stories_rounded,
              size: 20,
              color: _service.allowDuringQuran ? p.accent : p.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                context.l10n.ambientAllowDuringQuran,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            PulsrSwitch(
              value: _service.allowDuringQuran,
              onChanged: (v) => unawaited(_service.setAllowDuringQuran(v)),
            ),
          ],
        ),
      ],
    );

    if (!widget.showContainerDecoration) {
      return Padding(
        padding: widget.padding ?? EdgeInsets.zero,
        child: content,
      );
    }

    return Padding(
      padding: widget.padding ?? EdgeInsets.zero,
      child: AnimatedContainer(
        duration: context.motion(PulsrMotion.layout),
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: AppRadii.r14All,
          border: Border.all(
            color: _service.isEnabled
                ? p.accent.withValues(alpha: 0.35)
                : p.hairline,
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.s14),
        child: content,
      ),
    );
  }
}

// ─── Status badge ─────────────────────────────────────────────────────────────

class AmbientStatusBadge extends StatelessWidget {
  final bool isPlaying;
  final dynamic palette;

  const AmbientStatusBadge({super.key, required this.isPlaying, required this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: isPlaying
            ? p.accent.withValues(alpha: 0.15)
            : p.textTertiary.withValues(alpha: 0.15),
        borderRadius: AppRadii.r12All,
        border: Border.all(
          color: isPlaying ? p.accent.withValues(alpha: 0.35) : p.hairline,
          width: 0.8,
        ),
      ),
      child: Text(
        isPlaying
            ? context.l10n.ambientStatusPlaying
            : context.l10n.ambientStatusPaused,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isPlaying ? p.accent : p.textSecondary,
        ),
      ),
    );
  }
}

typedef _StatusBadge = AmbientStatusBadge;

// ─── Active count badge ───────────────────────────────────────────────────────

class AmbientActiveBadge extends StatelessWidget {
  final int count;
  final dynamic palette;

  const AmbientActiveBadge({super.key, required this.count, required this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.15),
        borderRadius: AppRadii.r12All,
        border: Border.all(
          color: p.accent.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Text(
        context.l10n.ambientActiveCount(count).toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: p.accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

typedef _ActiveBadge = AmbientActiveBadge;

// ─── Master volume row ────────────────────────────────────────────────────────

class _MasterVolumeRow extends StatelessWidget {
  final String label;
  final double volume;
  final dynamic palette;
  final ValueChanged<double> onChanged;

  const _MasterVolumeRow({
    required this.label,
    required this.volume,
    required this.palette,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Row(
      children: [
        Icon(Icons.volume_up_rounded, size: 16, color: p.accent),
        const SizedBox(width: 6),
        Expanded(
          child: Slider(
            value: volume,
            onChanged: onChanged,
            label: label,
            activeColor: p.accent,
            inactiveColor: p.hairline,
            semanticFormatterCallback: (v) => '$label ${(v * 100).round()}%',
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '${(volume * 100).round()}%',
            style: TextStyle(
              color: p.accent,
              fontSize: AppFontSize.label,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

// ─── Volume row ───────────────────────────────────────────────────────────────

class _VolumeRow extends StatelessWidget {
  final AmbientSoundEffect effect;
  final double volume;
  final dynamic palette;
  final ValueChanged<double> onChanged;

  const _VolumeRow({
    required this.effect,
    required this.volume,
    required this.palette,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text(effect.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: Text(
              effect.localizedLabel(context.l10n),
              style: TextStyle(
                color: p.textPrimary,
                fontSize: AppFontSize.label,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: volume,
                onChanged: onChanged,
                activeColor: p.accent,
                inactiveColor: p.hairline,
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${(volume * 100).round()}%',
              style: TextStyle(
                color: p.accent,
                fontSize: AppFontSize.label,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
