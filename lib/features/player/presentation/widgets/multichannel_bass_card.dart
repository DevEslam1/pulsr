// lib/features/player/presentation/widgets/multichannel_bass_card.dart
import 'dart:async';
import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../data/audio/audio_effects_channel.dart';
import '../../../../data/audio/equalizer_manager.dart';
import '../../../../domain/models/audio_channel_layout.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../settings/cubit/settings_cubit.dart';

/// Per-channel gain trim / delay alignment and LFE bass management card.
/// Shown when the audio output device or current stream reports >2 channels
/// (AAudio is limited to 2 channels on Android; multichannel streams >2 ch
/// route via Pulsr's 32-bit float AudioTrack path).
class MultichannelBassCard extends StatefulWidget {
  final String? blockedReason;
  final bool nativeAvailable;
  final bool forceVisible;

  const MultichannelBassCard({
    super.key,
    this.blockedReason,
    this.nativeAvailable = true,
    this.forceVisible = false,
  });

  @override
  State<MultichannelBassCard> createState() => _MultichannelBassCardState();
}

class _MultichannelBassCardState extends State<MultichannelBassCard> {
  bool _channelManagerEnabled = false;
  int _channelCount = 6; // default 5.1
  int _selectedChannel = 0;
  List<double> _channelTrims = List<double>.filled(8, 0.0);
  List<double> _channelDelays = List<double>.filled(8, 0.0);

  bool _lfeCrossoverEnabled = false;
  double _lfeCrossoverHz = 80.0;
  double _lfeLowPassHz = 120.0;
  double _lfeSlopeDbPerOct = 24.0;
  double _lfeGainDb = 0.0;
  int _lfeChannelIndex = 3;
  bool _lfeRedirectBass = true;

  bool _loaded = false;

  AudioChannelLayout? get _layout =>
      AudioChannelLayout.fromChannelCount(_channelCount);

  static List<double> _normalizeEight(List<double> raw) {
    final out = List<double>.filled(8, 0.0);
    final n = raw.length < 8 ? raw.length : 8;
    for (int i = 0; i < n; ++i) {
      if (raw[i].isFinite) out[i] = raw[i];
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      if (getIt.isRegistered<EqualizerManager>()) {
        final eq = getIt<EqualizerManager>();
        _channelManagerEnabled = eq.isChannelManagerEnabled;
        _channelCount = eq.channelManagerChannelCount.clamp(2, 8);
        _channelTrims = _normalizeEight(eq.channelManagerTrimDb);
        _channelDelays = _normalizeEight(eq.channelManagerDelayMs);
        _lfeCrossoverEnabled = eq.isLfeCrossoverEnabled;
        _lfeCrossoverHz = eq.lfeCrossoverHz;
        _lfeLowPassHz = eq.lfeLowPassHz;
        _lfeSlopeDbPerOct = eq.lfeSlopeDbPerOct;
        _lfeGainDb = eq.lfeGainDb;
        _lfeChannelIndex = eq.lfeChannelIndex;
        _lfeRedirectBass = eq.lfeRedirectBass;
      } else {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        _channelManagerEnabled =
            prefs.getBool(PrefsKeys.channelManagerEnabled) ?? false;
        _channelCount =
            (prefs.getInt(PrefsKeys.channelManagerChannelCount) ?? 6)
                .clamp(2, 8);
        final rawTrims = prefs.getString(PrefsKeys.channelManagerTrims);
        if (rawTrims != null) {
          try {
            final raw = json.decode(rawTrims);
            if (raw is List) {
              _channelTrims = _normalizeEight(
                  raw.whereType<num>().map((e) => e.toDouble()).toList());
            }
          } catch (_) {}
        }
        final rawDelays = prefs.getString(PrefsKeys.channelManagerDelays);
        if (rawDelays != null) {
          try {
            final raw = json.decode(rawDelays);
            if (raw is List) {
              _channelDelays = _normalizeEight(
                  raw.whereType<num>().map((e) => e.toDouble()).toList());
            }
          } catch (_) {}
        }
        _lfeCrossoverEnabled =
            prefs.getBool(PrefsKeys.lfeCrossoverEnabled) ?? false;
        _lfeCrossoverHz = prefs.getDouble(PrefsKeys.lfeCrossoverHz) ?? 80.0;
        _lfeLowPassHz = prefs.getDouble(PrefsKeys.lfeLowPassHz) ?? 120.0;
        _lfeSlopeDbPerOct =
            prefs.getDouble(PrefsKeys.lfeSlopeDbPerOct) ?? 24.0;
        _lfeGainDb = prefs.getDouble(PrefsKeys.lfeGainDb) ?? 0.0;
        _lfeChannelIndex = (prefs.getInt(PrefsKeys.lfeChannelIndex) ?? 3)
            .clamp(0, 7);
        _lfeRedirectBass =
            prefs.getBool(PrefsKeys.lfeRedirectBass) ?? true;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to restore multichannel bass settings',
          error: e, stackTrace: st);
    }

    // Derive the layout from the stored count, falling back to the route's
    // real channel count when the stored value is stereo/unsupported. Never
    // keep an LFE stage alive on a layout that has no LFE channel.
    var layout = AudioChannelLayout.fromChannelCount(_channelCount);
    if ((layout == null || layout.channelCount <= 2) &&
        getIt.isRegistered<SettingsCubit>()) {
      final outputChannels = getIt<SettingsCubit>()
          .state
          .currentOutputDevice
          ?.effectiveOutputChannels;
      final fromRoute = AudioChannelLayout.fromChannelCount(outputChannels);
      if (fromRoute != null && fromRoute.channelCount > 2) {
        layout = fromRoute;
        _channelCount = fromRoute.channelCount;
      }
    }
    if (layout != null) {
      _lfeChannelIndex = layout.lfeIndex < 0 ? 0 : layout.lfeIndex;
      if (!layout.hasLfe) _lfeCrossoverEnabled = false;
    }
    if (_selectedChannel >= _channelCount) {
      _selectedChannel = _channelCount - 1;
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _setChannelManagerEnabled(bool enabled) async {
    setState(() => _channelManagerEnabled = enabled);
    try {
      if (getIt.isRegistered<EqualizerManager>()) {
        await getIt<EqualizerManager>()
            .setChannelManagerEnabled(enabled, channelCount: _channelCount);
      } else {
        await AudioEffectsChannel()
            .setChannelManagerEnabled(enabled, channelCount: _channelCount);
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        await prefs.setBool(PrefsKeys.channelManagerEnabled, enabled);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to toggle channel manager',
          error: e, stackTrace: st, category: 'ChannelManager');
      if (mounted) setState(() => _channelManagerEnabled = !enabled);
    }
  }

  Future<void> _selectLayout(AudioChannelLayout layout) async {
    if (!AudioChannelLayout.offered.contains(layout)) return;
    final prevCount = _channelCount;
    final prevLfeEnabled = _lfeCrossoverEnabled;
    final prevLfeIndex = _lfeChannelIndex;
    final prevSelected = _selectedChannel;
    final targetLfeEnabled = layout.hasLfe ? _lfeCrossoverEnabled : false;
    final targetLfeIndex = layout.lfeIndex < 0 ? 0 : layout.lfeIndex;

    setState(() {
      _channelCount = layout.channelCount;
      _lfeChannelIndex = targetLfeIndex;
      _lfeCrossoverEnabled = targetLfeEnabled;
      if (_selectedChannel >= _channelCount) {
        _selectedChannel = _channelCount - 1;
      }
    });
    try {
      if (getIt.isRegistered<EqualizerManager>()) {
        await getIt<EqualizerManager>().setChannelLayout(
          layout,
          enabled: _channelManagerEnabled,
        );
      } else {
        // Fallback without the manager: push the layout, every channel value
        // and the LFE stage as one decision.
        final channel = AudioEffectsChannel();
        await channel.setChannelManagerEnabled(
          _channelManagerEnabled,
          channelCount: layout.channelCount,
        );
        for (int ch = 0; ch < 8; ++ch) {
          await channel.setChannelManagerChannel(
            ch,
            trimDb: _channelTrims[ch],
            delayMs: _channelDelays[ch],
          );
        }
        await channel.setLfeCrossoverParams(
          crossoverHz: _lfeCrossoverHz,
          lfeLowPassHz: _lfeLowPassHz,
          slopeDbPerOct: _lfeSlopeDbPerOct,
          lfeGainDb: _lfeGainDb,
          lfeChannelIndex: targetLfeIndex,
          redirectBass: _lfeRedirectBass,
        );
        await channel.setLfeCrossoverEnabled(targetLfeEnabled);
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        await prefs.setInt(
            PrefsKeys.channelManagerChannelCount, layout.channelCount);
        await prefs.setInt(PrefsKeys.lfeChannelIndex, targetLfeIndex);
        await prefs.setBool(PrefsKeys.lfeCrossoverEnabled, targetLfeEnabled);
      }
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _channelCount = prevCount;
          _lfeCrossoverEnabled = prevLfeEnabled;
          _lfeChannelIndex = prevLfeIndex;
          _selectedChannel = prevSelected;
        });
      }
      ErrorLogger.log('Failed to apply channel layout',
          error: e, stackTrace: st);
    }
  }

  Future<void> _setChannelParam(int channel,
      {double? trimDb, double? delayMs}) async {
    if (channel < 0 || channel >= 8) return;
    setState(() {
      if (trimDb != null) _channelTrims[channel] = trimDb;
      if (delayMs != null) _channelDelays[channel] = delayMs;
    });
    try {
      if (getIt.isRegistered<EqualizerManager>()) {
        await getIt<EqualizerManager>().setChannelManagerChannel(
          channel,
          trimDb: trimDb ?? _channelTrims[channel],
          delayMs: delayMs ?? _channelDelays[channel],
        );
      } else {
        await AudioEffectsChannel().setChannelManagerChannel(
          channel,
          trimDb: trimDb ?? _channelTrims[channel],
          delayMs: delayMs ?? _channelDelays[channel],
        );
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        await prefs.setString(
            PrefsKeys.channelManagerTrims, json.encode(_channelTrims));
        await prefs.setString(
            PrefsKeys.channelManagerDelays, json.encode(_channelDelays));
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set channel param',
          error: e, stackTrace: st, category: 'ChannelManager');
    }
  }

  Future<void> _setLfeCrossover({
    bool? enabled,
    double? crossoverHz,
    double? lowPassHz,
    double? slopeDbPerOct,
    double? lfeGainDb,
    int? lfeChannelIndex,
    bool? redirectBass,
  }) async {
    final targetEnabled = enabled ?? _lfeCrossoverEnabled;
    final targetCrossover = crossoverHz ?? _lfeCrossoverHz;
    final targetLowPass = lowPassHz ?? _lfeLowPassHz;
    final targetSlope = slopeDbPerOct ?? _lfeSlopeDbPerOct;
    final targetGain = lfeGainDb ?? _lfeGainDb;
    final targetLfeIndex = lfeChannelIndex ?? _lfeChannelIndex;
    final targetRedirect = redirectBass ?? _lfeRedirectBass;

    setState(() {
      _lfeCrossoverEnabled = targetEnabled;
      _lfeCrossoverHz = targetCrossover;
      _lfeLowPassHz = targetLowPass;
      _lfeSlopeDbPerOct = targetSlope;
      _lfeGainDb = targetGain;
      _lfeChannelIndex = targetLfeIndex;
      _lfeRedirectBass = targetRedirect;
    });

    try {
      if (getIt.isRegistered<EqualizerManager>()) {
        await getIt<EqualizerManager>().setLfeCrossover(
          targetEnabled,
          crossoverHz: targetCrossover,
          lfeLowPassHz: targetLowPass,
          slopeDbPerOct: targetSlope,
          lfeGainDb: targetGain,
          lfeChannelIndex: targetLfeIndex,
          redirectBass: targetRedirect,
        );
      } else {
        await AudioEffectsChannel().setLfeCrossoverParams(
          crossoverHz: targetCrossover,
          lfeLowPassHz: targetLowPass,
          slopeDbPerOct: targetSlope,
          lfeGainDb: targetGain,
          lfeChannelIndex: targetLfeIndex,
          redirectBass: targetRedirect,
        );
        await AudioEffectsChannel()
            .setLfeCrossoverEnabled(targetEnabled);
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        await prefs.setBool(PrefsKeys.lfeCrossoverEnabled, targetEnabled);
        await prefs.setDouble(PrefsKeys.lfeCrossoverHz, targetCrossover);
        await prefs.setDouble(PrefsKeys.lfeLowPassHz, targetLowPass);
        await prefs.setDouble(PrefsKeys.lfeSlopeDbPerOct, targetSlope);
        await prefs.setDouble(PrefsKeys.lfeGainDb, targetGain);
        await prefs.setInt(PrefsKeys.lfeChannelIndex, targetLfeIndex);
        await prefs.setBool(PrefsKeys.lfeRedirectBass, targetRedirect);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set LFE crossover',
          error: e, stackTrace: st, category: 'ChannelManager');
    }
  }

  void _showInfo(AudioFeatureInfo info) {
    PulsrDialogHelper.showPulsrDialog<void>(
      context,
      icon: Icon(Icons.info_outline_rounded,
          color: context.palette.accent, size: 26),
      title: Text(info.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(info.subtitle,
                style: TextStyle(
                    color: context.palette.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: AppFontSize.label)),
            const SizedBox(height: AppSpacing.s10),
            Text(info.description,
                style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: AppFontSize.bodySmall,
                    height: 1.4)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final output = context.select<SettingsCubit?, AudioOutputInfo?>(
        (c) => c?.state.currentOutputDevice);
    final isMultichannel =
        widget.forceVisible || (output?.hasMultichannelOutput ?? false);
    final hasLfe = _layout?.hasLfe ?? false;

    if (!isMultichannel) {
      return const SizedBox.shrink();
    }

    if (!_loaded) {
      return const SizedBox.shrink();
    }

    final p = context.palette;
    final dspBlocked = widget.blockedReason;
    final isBlocked = dspBlocked != null || !widget.nativeAvailable;

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
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  borderRadius: AppRadii.r8All,
                ),
                child: Icon(Icons.surround_sound_rounded,
                    color: p.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Multichannel Speaker Alignment',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.body,
                        color: p.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Per-channel trim, alignment delay & LFE crossover',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: p.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    size: 16, color: p.textTertiary),
                tooltip: 'Multichannel Info',
                onPressed: () => _showInfo(AudioFeatureRegistry.channelManager),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: !isBlocked && _channelManagerEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: isBlocked
                    ? null
                    : (val) => _setChannelManagerEnabled(val),
              ),
            ],
          ),

          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(
                'Bypassed by Bit-Perfect Mode',
                style: TextStyle(
                  color: p.error,
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.sm),

          // AAudio 2-ch Limit & AudioTrack Explanatory Note
          Container(
            padding: const EdgeInsets.all(AppSpacing.s10),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.08),
              borderRadius: AppRadii.r10All,
              border: Border.all(color: p.accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: p.accent),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'AAudio is limited to 2 channels on Android; multichannel streams (>2 ch) route through Pulsr\'s 32-bit float AudioTrack path for genuine surround output.',
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: p.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (!isBlocked && _channelManagerEnabled) ...[
            const SizedBox(height: AppSpacing.md),

            // Channel Layout Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Speaker Layout',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: p.textSecondary,
                  ),
                ),
                Text(
                  '${_layout?.displayName ?? '$_channelCount ch'} '
                  '($_channelCount channels)',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final layout in AudioChannelLayout.offered)
                  _buildLayoutChip(
                    p,
                    layout,
                    '${layout.displayName} (${layout.channelCount} ch)',
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AudioChannelLayout.twoOnePlatformNote,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: p.textTertiary,
                height: 1.3,
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Channel Selector Tabs
            Text(
              'Select Speaker Channel',
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w700,
                color: p.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_channelCount, (i) {
                  final isSelected = i == _selectedChannel;
                  final label = _layout?.labelAt(i) ?? 'CH $i';
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      selectedColor: p.accent,
                      labelStyle: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? p.onAccent : p.textSecondary,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedChannel = i);
                      },
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Per-Channel Controls Container
            Container(
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: p.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: AppRadii.r12All,
                border: Border.all(color: p.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speaker_rounded, size: 16, color: p.accent),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        _layout?.fullNameAt(_selectedChannel) ??
                            'Channel $_selectedChannel',
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Gain Trim Slider
                  _buildSliderRow(
                    p: p,
                    label: 'Gain Trim',
                    valueText:
                        '${_channelTrims[_selectedChannel] >= 0 ? '+' : ''}${_channelTrims[_selectedChannel].toStringAsFixed(1)} dB',
                    value: _channelTrims[_selectedChannel],
                    min: -30.0,
                    max: 12.0,
                    defaultValue: 0.0,
                    divisions: 84,
                    onChanged: (val) =>
                        _setChannelParam(_selectedChannel, trimDb: val),
                  ),

                  // Delay Slider
                  _buildSliderRow(
                    p: p,
                    label: 'Alignment Delay',
                    valueText:
                        '${_channelDelays[_selectedChannel].toStringAsFixed(1)} ms',
                    value: _channelDelays[_selectedChannel],
                    min: 0.0,
                    max: 50.0,
                    defaultValue: 0.0,
                    divisions: 100,
                    onChanged: (val) =>
                        _setChannelParam(_selectedChannel, delayMs: val),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: AppSpacing.md),

          // LFE Crossover & Dedicated Subwoofer Section
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  borderRadius: AppRadii.r8All,
                ),
                child: Icon(Icons.speaker_group_rounded,
                    color: p.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LFE Crossover & Bass Management',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.body,
                        color: p.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Satellite HPF & dedicated subwoofer crossover',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: p.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    size: 16, color: p.textTertiary),
                tooltip: 'LFE Crossover Info',
                onPressed: () => _showInfo(AudioFeatureRegistry.lfeCrossover),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: !isBlocked && hasLfe && _lfeCrossoverEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: (isBlocked || !hasLfe)
                    ? null
                    : (val) => _setLfeCrossover(enabled: val),
              ),
            ],
          ),

          if (!isBlocked && hasLfe && _lfeCrossoverEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Linkwitz-Riley crossover applies high-pass filter to satellite channels and routes redirected low frequencies to the dedicated LFE channel.',
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: p.textTertiary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: AppSpacing.s10),

            // Satellite Crossover Frequency
            _buildSliderRow(
              p: p,
              label: 'Satellite Crossover (HPF)',
              valueText: '${_lfeCrossoverHz.round()} Hz',
              value: _lfeCrossoverHz,
              min: 40.0,
              max: 200.0,
              defaultValue: 80.0,
              divisions: 32,
              onChanged: (val) => _setLfeCrossover(crossoverHz: val),
            ),

            // Dedicated LFE Low-Pass
            _buildSliderRow(
              p: p,
              label: 'Subwoofer Low-Pass (LPF)',
              valueText: '${_lfeLowPassHz.round()} Hz',
              value: _lfeLowPassHz,
              min: 60.0,
              max: 250.0,
              defaultValue: 120.0,
              divisions: 38,
              onChanged: (val) => _setLfeCrossover(lowPassHz: val),
            ),

            // Filter Slope
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crossover Filter Slope',
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('12 dB/oct (LR2)'),
                      selected: _lfeSlopeDbPerOct < 18.0,
                      selectedColor: p.accent,
                      labelStyle: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        color: _lfeSlopeDbPerOct < 18.0
                            ? p.onAccent
                            : p.textSecondary,
                      ),
                      onSelected: (val) {
                        if (val) _setLfeCrossover(slopeDbPerOct: 12.0);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('24 dB/oct (LR4)'),
                      selected: _lfeSlopeDbPerOct >= 18.0,
                      selectedColor: p.accent,
                      labelStyle: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        color: _lfeSlopeDbPerOct >= 18.0
                            ? p.onAccent
                            : p.textSecondary,
                      ),
                      onSelected: (val) {
                        if (val) _setLfeCrossover(slopeDbPerOct: 24.0);
                      },
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),

            // LFE Gain Trim
            _buildSliderRow(
              p: p,
              label: 'LFE Channel Gain Trim',
              valueText:
                  '${_lfeGainDb >= 0 ? '+' : ''}${_lfeGainDb.toStringAsFixed(1)} dB',
              value: _lfeGainDb,
              min: -12.0,
              max: 12.0,
              defaultValue: 0.0,
              divisions: 48,
              onChanged: (val) => _setLfeCrossover(lfeGainDb: val),
            ),

            const SizedBox(height: AppSpacing.xs),

            // Redirect Satellite Bass Switch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Redirect Satellite Bass',
                        style: TextStyle(
                          fontSize: AppFontSize.body,
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Sums satellite frequencies below crossover into LFE with 1/√(N-1) power normalization.',
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          color: p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Switch.adaptive(
                  value: _lfeRedirectBass,
                  activeThumbColor: p.onAccent,
                  activeTrackColor: p.accent,
                  onChanged: (v) => _setLfeCrossover(redirectBass: v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLayoutChip(
      PulsrPalette p, AudioChannelLayout layout, String label) {
    final isSelected = _channelCount == layout.channelCount;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: p.accent,
      labelStyle: TextStyle(
        fontSize: AppFontSize.caption,
        fontWeight: FontWeight.w700,
        color: isSelected ? p.onAccent : p.textSecondary,
      ),
      onSelected: (val) {
        if (val) _selectLayout(layout);
      },
    );
  }

  Widget _buildSliderRow({
    required PulsrPalette p,
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required double defaultValue,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  color: p.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  valueText,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.settings_backup_restore,
                    size: 15,
                    color: (value - defaultValue).abs() < 0.01
                        ? p.textTertiary.withValues(alpha: 0.35)
                        : p.accent,
                  ),
                  tooltip: 'Reset',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: (value - defaultValue).abs() < 0.01
                      ? null
                      : () => onChanged(defaultValue),
                ),
              ],
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: p.accent,
            inactiveTrackColor: p.surface,
            thumbColor: p.accent,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
