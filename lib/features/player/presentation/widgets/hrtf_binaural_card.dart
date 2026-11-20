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
import '../../../../core/utils/safe_file_path.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../core/widgets/throttled_slider.dart';
import '../../../../data/audio/equalizer_manager.dart';
import '../../cubit/player_cubit.dart';

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

  @override
  void initState() {
    super.initState();
    _restoreState();
  }

  void _restoreState() {
    if (getIt.isRegistered<EqualizerManager>()) {
      final eq = getIt<EqualizerManager>();
      _enabled = eq.isHrtfEnabled;
      _azimuth = eq.hrtfAzimuth;
      _elevation = eq.hrtfElevation;
      _sofaPath = eq.hrtfSofaPath;
    }
  }

  Future<void> _toggleEnabled(BuildContext context, bool enabled) async {
    final prev = _enabled;
    setState(() => _enabled = enabled);
    try {
      await context.read<PlayerCubit>().setHrtfBinaural(
            enabled,
            azimuth: _azimuth,
            elevation: _elevation,
            sofaPath: _sofaPath,
          );
    } catch (e, st) {
      if (mounted) setState(() => _enabled = prev);
      ErrorLogger.log('Failed to toggle HRTF', error: e, stackTrace: st);
    }
  }

  Future<void> _updateAzimuth(BuildContext context, double val) async {
    setState(() => _azimuth = val);
    try {
      await context.read<PlayerCubit>().setHrtfBinaural(
            _enabled,
            azimuth: val,
            elevation: _elevation,
            sofaPath: _sofaPath,
          );
    } catch (_) {}
  }

  Future<void> _updateElevation(BuildContext context, double val) async {
    setState(() => _elevation = val);
    try {
      await context.read<PlayerCubit>().setHrtfBinaural(
            _enabled,
            azimuth: _azimuth,
            elevation: val,
            sofaPath: _sofaPath,
          );
    } catch (_) {}
  }

  Future<void> _pickSofaFile(BuildContext context) async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['sofa', 'wav'],
      );
      if (result == null || result.path == null) return;

      final file = SafeFilePath.validate(
        result.path!,
        allowedExtensions: ['sofa', 'wav'],
      );
      if (file == null) {
        throw 'Invalid or inaccessible file';
      }

      final path = file.path;
      setState(() => _sofaPath = path);

      if (context.mounted) {
        await context.read<PlayerCubit>().setHrtfBinaural(
              _enabled,
              azimuth: _azimuth,
              elevation: _elevation,
              sofaPath: path,
            );
        if (context.mounted) {
          PulsrToast.show(
            context,
            message: 'Loaded HRTF dataset: ${result.name}',
            icon: Icons.check_circle_rounded,
          );
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to pick/load SOFA dataset', error: e, stackTrace: st);
      if (context.mounted) {
        PulsrToast.show(
          context,
          message: 'Failed to load SOFA/HRIR dataset',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _resetToDefault(BuildContext context) async {
    setState(() {
      _azimuth = 30.0;
      _elevation = 0.0;
      _sofaPath = null;
    });
    await context.read<PlayerCubit>().setHrtfBinaural(
          _enabled,
          azimuth: 30.0,
          elevation: 0.0,
          sofaPath: '',
        );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isCrossfeedActive = context.select<PlayerCubit, bool>(
      (c) => c.state.isCrossfeedEnabled,
    );
    final isBlocked = widget.blockedReason != null || !widget.nativeAvailable;

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
                child: Icon(Icons.spatial_audio_rounded,
                    color: p.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HRTF 3D Binaural Spatializer',
                      style: TextStyle(
                        fontSize: AppFontSize.body,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      'Partitioned SOFA/HRIR convolution for 3D realism',
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
                      'Blocked by Bit-Perfect (${widget.blockedReason})',
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
                      'Mutually exclusive: Engaging HRTF disables Headphone Crossfeed.',
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
                  'Virtual Speaker Azimuth',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                Text(
                  '${_azimuth.toStringAsFixed(0)}° (${_azimuth < 0 ? 'Left' : (_azimuth > 0 ? 'Right' : 'Center')})',
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
                  'Virtual Speaker Elevation',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                Text(
                  '${_elevation.toStringAsFixed(0)}° (${_elevation < 0 ? 'Below' : (_elevation > 0 ? 'Above' : 'Ear Level')})',
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
                          ? 'SOFA: ${_sofaPath!.split(RegExp(r'[/\\]')).last}'
                          : 'Load Custom SOFA / WAV...',
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
                  tooltip: 'Reset Azimuth / Elevation / Dataset',
                  onPressed: () => _resetToDefault(context),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
