// lib/features/player/presentation/widgets/hrtf_binaural_card.dart
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/safe_file_path.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../core/widgets/throttled_slider.dart';
import '../../../../data/audio/equalizer_manager.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

/// 3D HRTF Binaural Spatialization Card (§8.9 & §9).
/// Provides partitioned-convolution binaural synthesis with user-steerable
/// azimuth and elevation, NetCDF-3 SOFA / WAV HRIR loading, and strict
/// mutual exclusivity with Headphone Crossfeed and Bit-Perfect.
class HrtfBinauralCard extends StatefulWidget {
  final String? blockedReason;
  final bool nativeAvailable;

  const HrtfBinauralCard({
    super.key,
    this.blockedReason,
    this.nativeAvailable = true,
  });

  @override
  State<HrtfBinauralCard> createState() => _HrtfBinauralCardState();
}

class _HrtfBinauralCardState extends State<HrtfBinauralCard> {
  bool _enabled = false;
  double _azimuth = 30.0;
  double _elevation = 0.0;
  String? _sofaPath;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _restoreState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _restoreState();
    }
  }

  void _restoreState() {
    try {
      final playerState = context.read<PlayerCubit>().state;
      _enabled = playerState.isHrtfEnabled;
      _azimuth = playerState.hrtfAzimuth;
      _elevation = playerState.hrtfElevation;
      _sofaPath = playerState.hrtfSofaPath;
    } catch (_) {
      if (getIt.isRegistered<EqualizerManager>()) {
        final eq = getIt<EqualizerManager>();
        _enabled = eq.isHrtfEnabled;
        _azimuth = eq.hrtfAzimuth;
        _elevation = eq.hrtfElevation;
        _sofaPath = eq.hrtfSofaPath;
      }
    }
  }

  Future<bool> _applyHrtf(
    BuildContext context, {
    required bool enabled,
    required double azimuth,
    required double elevation,
    required String? sofaPath,
    bool verifyDatasetPath = false,
  }) async {
    final cubit = context.read<PlayerCubit>();
    final prevState = cubit.state;
    await cubit.setHrtfBinaural(
      enabled,
      azimuth: azimuth,
      elevation: elevation,
      sofaPath: sofaPath,
    );
    if (!mounted) return false;
    final after = cubit.state;
    final newError =
        after.errorMessage != null && after.errorMessage != prevState.errorMessage;
    final acknowledged = !verifyDatasetPath ||
        ((sofaPath == null || sofaPath.isEmpty)
            ? _hrtfDatasetAcknowledged('')
            : _hrtfDatasetAcknowledged(sofaPath));
    if (newError || !acknowledged) {
      _restoreState();
      setState(() {});
      return false;
    }
    final didEmitChange = !identical(after, prevState);
    setState(() {
      if (didEmitChange) {
        _enabled = after.isHrtfEnabled;
        _azimuth = after.hrtfAzimuth;
        _elevation = after.hrtfElevation;
        _sofaPath =
            (after.hrtfSofaPath?.isEmpty ?? true) ? null : after.hrtfSofaPath;
      } else {
        _enabled = enabled;
        _azimuth = azimuth;
        _elevation = elevation;
        _sofaPath = (sofaPath?.isEmpty ?? true) ? null : sofaPath;
      }
    });
    return true;
  }

  Future<void> _toggleEnabled(BuildContext context, bool enabled) async {
    try {
      await _applyHrtf(
        context,
        enabled: enabled,
        azimuth: _azimuth,
        elevation: _elevation,
        sofaPath: _sofaPath,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to toggle HRTF', error: e, stackTrace: st);
    }
  }

  Future<void> _updateAzimuth(BuildContext context, double val) async {
    try {
      await _applyHrtf(
        context,
        enabled: _enabled,
        azimuth: val,
        elevation: _elevation,
        sofaPath: _sofaPath,
      );
    } catch (_) {}
  }

  Future<void> _updateElevation(BuildContext context, double val) async {
    try {
      await _applyHrtf(
        context,
        enabled: _enabled,
        azimuth: _azimuth,
        elevation: val,
        sofaPath: _sofaPath,
      );
    } catch (_) {}
  }

  /// True when the manager actually adopted [path]. The cubit's
  /// applyDspEffect swallows native failures and only rolls back the stored
  /// dataset path, so the card cannot rely on an exception to detect a
  /// rejected SOFA/HRIR file.
  bool _hrtfDatasetAcknowledged(String path) {
    if (!getIt.isRegistered<EqualizerManager>()) return true;
    final stored = getIt<EqualizerManager>().hrtfSofaPath;
    if (path.isEmpty) return stored == null || stored.isEmpty;
    return stored == path;
  }

  Future<void> _pickSofaFile(BuildContext context) async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['sofa', 'wav'],
      );
      if (!mounted) return;
      if (result == null || result.path == null) return;

      final file = SafeFilePath.validate(
        result.path!,
        allowedExtensions: ['sofa', 'wav'],
      );
      if (file == null) {
        throw 'Invalid or inaccessible file';
      }

      final path = file.path;

      if (context.mounted) {
        final confirmed = await _applyHrtf(
          context,
          enabled: _enabled,
          azimuth: _azimuth,
          elevation: _elevation,
          sofaPath: path,
          verifyDatasetPath: true,
        );
        if (!confirmed) {
          throw StateError('Native HRTF dataset load was rejected');
        }
        if (context.mounted) {
          PulsrToast.show(
            context,
            message: context.l10n.hrtfDatasetLoadedToast(result.name),
            icon: Icons.check_circle_rounded,
          );
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to pick/load SOFA dataset', error: e, stackTrace: st);
      if (context.mounted) {
        PulsrToast.show(
          context,
          message: context.l10n.hrtfDatasetLoadFailedToast,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _resetToDefault(BuildContext context) async {
    try {
      await _applyHrtf(
        context,
        enabled: _enabled,
        azimuth: 30.0,
        elevation: 0.0,
        sofaPath: '',
        verifyDatasetPath: true,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to reset HRTF dataset', error: e, stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final isCrossfeedActive = context.select<PlayerCubit, bool>(
      (c) => c.state.isCrossfeedEnabled,
    );
    final isBlocked = widget.blockedReason != null || !widget.nativeAvailable;

    return BlocListener<PlayerCubit, PlayerState>(
      listenWhen: (prev, curr) =>
          prev.isHrtfEnabled != curr.isHrtfEnabled ||
          prev.hrtfAzimuth != curr.hrtfAzimuth ||
          prev.hrtfElevation != curr.hrtfElevation ||
          prev.hrtfSofaPath != curr.hrtfSofaPath,
      listener: (context, state) {
        setState(() {
          _enabled = state.isHrtfEnabled;
          _azimuth = state.hrtfAzimuth;
          _elevation = state.hrtfElevation;
          _sofaPath = state.hrtfSofaPath;
        });
      },
      child: Container(
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
                child: Icon(Icons.spatial_audio_rounded,
                    color: p.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hrtfTitle,
                      style: TextStyle(
                        fontSize: AppFontSize.body,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      l10n.hrtfSubtitle,
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _enabled && !isBlocked,
                onChanged: isBlocked
                    ? null
                    : (val) => _toggleEnabled(context, val),
              ),
            ],
          ),

          if (widget.blockedReason != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: p.error.withValues(alpha: 0.1),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.block_rounded, color: p.error, size: 16),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.hrtfBlockedByBitPerfect(widget.blockedReason!),
                      style: TextStyle(
                          fontSize: AppFontSize.caption, color: p.error),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isCrossfeedActive && _enabled) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.1),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: p.accent, size: 16),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.hrtfCrossfeedConflict,
                      style: TextStyle(
                          fontSize: AppFontSize.caption, color: p.accent),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_enabled && !isBlocked) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),

            // Azimuth Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.hrtfVirtualSpeakerAzimuth,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                Text(
                  l10n.hrtfAngleDirection(
                    _azimuth.toStringAsFixed(0),
                    _azimuth < 0
                        ? l10n.hrtfDirectionLeft
                        : (_azimuth > 0
                            ? l10n.hrtfDirectionRight
                            : l10n.hrtfDirectionCenter),
                  ),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
              ],
            ),
            ThrottledSlider(
              value: _azimuth,
              min: -90.0,
              max: 90.0,
              divisions: 36,
              onChanged: (val) => _updateAzimuth(context, val),
            ),

            const SizedBox(height: AppSpacing.sm),

            // Elevation Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.hrtfVirtualSpeakerElevation,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                Text(
                  l10n.hrtfAngleDirection(
                    _elevation.toStringAsFixed(0),
                    _elevation < 0
                        ? l10n.hrtfElevationBelow
                        : (_elevation > 0
                            ? l10n.hrtfElevationAbove
                            : l10n.hrtfElevationEarLevel),
                  ),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
              ],
            ),
            ThrottledSlider(
              value: _elevation,
              min: -45.0,
              max: 45.0,
              divisions: 18,
              onChanged: (val) => _updateElevation(context, val),
            ),

            const SizedBox(height: AppSpacing.sm),

            // Dataset selection row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.file_open_rounded, size: 16),
                    label: Text(
                      _sofaPath != null && _sofaPath!.isNotEmpty
                          ? l10n.hrtfSofaLoadedLabel(
                              _sofaPath!.split(RegExp(r'[/\\]')).last,
                            )
                          : l10n.hrtfLoadCustomSofa,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: AppFontSize.caption),
                    ),
                    onPressed: () => _pickSofaFile(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: l10n.hrtfResetTooltip,
                  onPressed: () => _resetToDefault(context),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
    );
  }
}
