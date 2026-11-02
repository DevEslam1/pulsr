import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/ambient_sound_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';

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

  const AmbientSoundPanel({
    super.key,
    this.padding,
    this.showContainerDecoration = true,
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
                      ],
                    ],
                  ),
                  Text(
                    _service.isEnabled && !_service.isPlayerPlaying
                        ? 'Paused with player'
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
            // Active count badge
            if (_service.isEnabled)
              Container(
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
                  '${_service.activeEffects.length} ON',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: p.accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),

        // ── Error ─────────────────────────────────────────────────────────────
        if (_service.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _service.errorMessage!,
            style: TextStyle(color: p.error, fontSize: AppFontSize.label),
          ),
        ],

        const SizedBox(height: AppSpacing.s10),
        Divider(height: 1, color: p.hairline),
        const SizedBox(height: AppSpacing.s10),

        // ── Effect chips ──────────────────────────────────────────────────────
        Text(
          'EFFECTS',
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
              label: effect.displayName,
              selected: selected,
              child: ChoiceChip(
                selected: selected,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  unawaited(_service.toggleEffect(effect));
                },
                avatar: Text(
                  effect.emoji,
                  style: const TextStyle(fontSize: 16),
                ),
                label: Text(effect.label),
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
            'VOLUMES',
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
        ],
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
        duration: const Duration(milliseconds: 250),
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

class _StatusBadge extends StatelessWidget {
  final bool isPlaying;
  final dynamic palette;

  const _StatusBadge({required this.isPlaying, required this.palette});

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
        isPlaying ? 'Playing' : 'Paused',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isPlaying ? p.accent : p.textSecondary,
        ),
      ),
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
              effect.label,
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
