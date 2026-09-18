// lib/features/sheets/song_info_sheet.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants/channels.dart';
import '../../core/di/injection.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/utils/platform_capabilities.dart';
import '../../core/widgets/cached_artwork.dart';
import '../../core/widgets/pulsr_dialog.dart';
import '../../core/widgets/pulsr_slider.dart';
import '../../data/audio/bpm_override_store.dart';
import '../../data/audio/headphone_profiles_repository.dart';
import '../../data/audio/per_song_eq_store.dart';
import '../../data/audio/per_song_volume_store.dart';
import '../../data/audio/song_rating_store.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/audio_quality_info.dart';
import '../../domain/models/eq_preset.dart';
import '../player/cubit/player_cubit.dart';
import '../player/presentation/widgets/audio_quality_badge.dart';
import '../../core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class SongInfoSheet extends StatelessWidget {
  final SongsTableData song;

  const SongInfoSheet({super.key, required this.song});

  static Future<void> show(BuildContext context, {required SongsTableData song}) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => SongInfoSheet(song: song),
    );
  }

  Future<void> _shareSong(BuildContext context) async {
    final text =
        '${context.l10n.browseCheckOut} "${song.title}" ${context.l10n.browseBy} ${song.artist} ${context.l10n.browseOnPulsr}';
    if (song.path.isNotEmpty && !song.path.startsWith('ytmusic://')) {
      final exists = await File(song.path).exists();
      if (exists) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(song.path)], text: text),
        );
        return;
      }
    }
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _setRingtone(BuildContext context, String type) async {
    const channel = MethodChannel(PulsrChannels.ringtone);
    final label = type == 'notification'
        ? context.l10n.browseNotificationSound
        : type == 'alarm'
            ? context.l10n.browseAlarmSound
            : context.l10n.ringtone;

    try {
      if (Platform.isAndroid) {
        final canWrite =
            await channel.invokeMethod<bool>('checkWriteSettingsPermission') ??
                true;
        if (!canWrite) {
          if (!context.mounted) return;
          final proceed = await PulsrDialogHelper.showConfirmDialog(
            context,
            title: context.l10n.permissionRequired,
            message:
                '${context.l10n.browseToSet} $label ${context.l10n.browseRequiresModifySettings}',
            icon: Icons.security_rounded,
            confirmLabel: context.l10n.openSettings,
            cancelLabel: context.l10n.cancel,
          );
          if (proceed == true) {
            channel.invokeMethod('openWriteSettings');
          }
          return;
        }
      }

      final success = await channel.invokeMethod<bool>('setRingtone', {
        'filePath': song.path,
        'type': type,
      });
      if (context.mounted && (success ?? false)) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ringtoneSet)),
        );
      }
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'PERMISSION_DENIED') {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.ringtoneFailed),
            action: SnackBarAction(
              label: context.l10n.settings,
              onPressed: () {
                channel.invokeMethod('openWriteSettings');
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${context.l10n.ringtoneFailed} ${e.message}')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.l10n.ringtoneFailed} $e')),
      );
    }
  }

  void _showRingtoneOptions(BuildContext context) {
    final p = context.palette;
    PulsrSheetHelper.showPulsrSheet(
      context: context,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                context.l10n.setAudioAs,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                    ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            ListTile(
              leading: Icon(Icons.ring_volume_rounded, color: p.accent),
              title: Text(context.l10n.phoneRingtone,
                  style: TextStyle(color: p.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _setRingtone(context, 'ringtone');
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.notifications_active_rounded, color: p.accent),
              title: Text(context.l10n.notificationSound,
                  style: TextStyle(color: p.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _setRingtone(context, 'notification');
              },
            ),
            ListTile(
              leading: Icon(Icons.alarm_rounded, color: p.accent),
              title: Text(context.l10n.alarmSound,
                  style: TextStyle(color: p.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _setRingtone(context, 'alarm');
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulsrBottomSheetContainer(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.s10, AppSpacing.s20, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                      CachedArtwork(
                        id: song.id,
                        remoteUrl: song.remoteArtworkUrl,
                        type: ArtworkType.AUDIO,
                        size: 64,
                        borderRadius: 14,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: p.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  Divider(color: p.hairline),
                  const SizedBox(height: AppSpacing.xs),
                  Builder(
                    builder: (context) {
                      final quality = AudioQualityInfo.fromSong(song);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                context.l10n.qualityAndCodec,
                                style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: AppTracking.wide,
                                  color: p.textSecondary,
                                ),
                              ),
                              AudioQualityBadge(
                                  song: song,
                                  activeColor: p.accent,
                                  compact: true),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _buildInfoRow(
                              context.l10n.audioFormat, quality.format, p),
                          if (quality.bitrateKbps != null)
                            _buildInfoRow(
                                context.l10n.bitrate,
                                '${quality.bitrateKbps} kbps (${quality.tierLabel})',
                                p),
                          _buildInfoRow(context.l10n.sampleRate,
                              '${quality.bitDepth} / ${quality.sampleRate}', p),
                          _buildInfoRow(
                              context.l10n.channels, quality.channels, p),
                          const SizedBox(height: AppSpacing.s6),
                          Divider(color: p.hairline),
                          const SizedBox(height: AppSpacing.s6),
                        ],
                      );
                    },
                  ),
                  _buildInfoRow(context.l10n.album, song.album, p),
                  _buildInfoRow(
                      context.l10n.duration,
                      Formatters.formatDuration(
                          Duration(milliseconds: song.durationMs)),
                      p),
                  _buildInfoRow(context.l10n.filePath, song.path, p),
                  _buildInfoRow(context.l10n.playCount,
                      context.l10n.playCountTimes(song.playCount), p),
                  if (song.fileSize != null)
                    _buildInfoRow(
                        context.l10n.fileSize,
                        '${(song.fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB',
                        p),
                  _buildAudioOverridesSection(context, p),
                  _buildPlaybackToolsSection(context, p),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadii.r14),
                            ),
                            side: BorderSide(color: p.hairline),
                          ),
                          onPressed: () => _shareSong(context),
                          icon: Icon(Icons.share_rounded,
                              size: 20, color: p.textPrimary),
                          label: Text(
                            context.l10n.share,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: p.textPrimary),
                          ),
                        ),
                      ),
                      if (PlatformCapabilities.hasRingtoneManager) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadii.r14),
                              ),
                              side: BorderSide(color: p.hairline),
                            ),
                            onPressed: () => _showRingtoneOptions(context),
                            icon: Icon(Icons.ring_volume_rounded,
                                size: 20, color: p.textPrimary),
                            label: Text(
                              context.l10n.ringtone,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: p.textPrimary),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (PlatformCapabilities.hasTagEditor)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: p.onAccent,
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          context.push('/tag-editor', extra: song);
                        },
                        icon: const Icon(Icons.edit_note_rounded, size: 20),
                        label: Text(
                          context.l10n.editTags,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: AppFontSize.callout),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }

  Widget _buildAudioOverridesSection(BuildContext context, PulsrPalette p) {
    final trackKey = song.id.toString();
    PlayerCubit? playerCubit;
    try {
      playerCubit = context.read<PlayerCubit>();
    } catch (_) {}
    final ratingStore = getIt.isRegistered<SongRatingStore>()
        ? getIt<SongRatingStore>()
        : SongRatingStore();
    final eqStore = getIt.isRegistered<PerSongEqStore>()
        ? getIt<PerSongEqStore>()
        : PerSongEqStore();
    final volStore = getIt.isRegistered<PerSongVolumeStore>()
        ? getIt<PerSongVolumeStore>()
        : PerSongVolumeStore();
    // BPM store has no DI registration (avoids graph regen); a local
    // instance shares the same SharedPreferences backing.
    final bpmStore = BpmOverrideStore();

    double currentSliderVol = volStore.getGainDbForTrack(trackKey);

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final currentRating = ratingStore.getRating(trackKey);
        final currentEq = eqStore.getPresetForTrack(trackKey);
        final currentBpm = bpmStore.getBpmForTrack(trackKey);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
          padding: const EdgeInsets.all(AppSpacing.s14),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadii.r16),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rating Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.l10n.trackRating,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                      color: p.textSecondary,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (index) {
                      final starNum = index + 1;
                      final isFilled = starNum <= currentRating;
                      return GestureDetector(
                        onTap: () async {
                          final newRating =
                              currentRating == starNum ? 0 : starNum;
                          await ratingStore.setRating(trackKey, newRating);
                          playerCubit?.setSongRating(song.id, newRating);
                          setLocalState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
                          child: Icon(
                            isFilled
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 22,
                            color: isFilled ? p.warning : p.textTertiary,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s10),
              Divider(color: p.hairline, height: 1),
              const SizedBox(height: AppSpacing.xs),

              // Per-Track EQ Preset Override
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.l10n.trackEqOverride,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                      color: p.textSecondary,
                    ),
                  ),
                  DropdownButton<String?>(
                    value: _eqDropdownValue(currentEq),
                    underline: const SizedBox(),
                    dropdownColor: p.surfaceContainer,
                    icon: Icon(Icons.arrow_drop_down, color: p.accent),
                    style: TextStyle(
                      color: currentEq != null ? p.accent : p.textPrimary,
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w600,
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(context.l10n.defaultGlobalEq),
                      ),
                      ...EqPreset.defaultPresets.map(
                        (preset) => DropdownMenuItem<String?>(
                          value: preset.name,
                          child: Text(preset.name),
                        ),
                      ),
                      // Custom + AutoEQ headphone profiles (resolved by name
                      // on auto-apply, same as built-in presets).
                      ...HeadphoneProfilesRepository()
                          .profiles
                          .where((hp) => EqPreset.defaultPresets.every(
                              (d) =>
                                  d.name.toLowerCase() !=
                                  hp.name.toLowerCase()))
                          .map(
                            (hp) => DropdownMenuItem<String?>(
                              value: hp.name,
                              child: Text('${hp.name} • AutoEQ'),
                            ),
                          ),
                    ],
                    onChanged: (newPreset) async {
                      await eqStore.setPresetForTrack(trackKey, newPreset);
                      playerCubit?.setSongEqOverride(song.id, newPreset);
                      setLocalState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Divider(color: p.hairline, height: 1),
              const SizedBox(height: AppSpacing.xs),

              // Per-Track Volume Offset
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.l10n.trackVolumeOffset,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                      color: p.textSecondary,
                    ),
                  ),
                  Text(
                    currentSliderVol.abs() < 0.1
                        ? '0.0 dB'
                        : '${currentSliderVol > 0 ? '+' : ''}${currentSliderVol.toStringAsFixed(1)} dB',
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                      color: currentSliderVol.abs() < 0.1 ? p.textSecondary : p.accent,
                    ),
                  ),
                ],
              ),
              PulsrSlider(
                value: currentSliderVol.clamp(-12.0, 6.0),
                min: -12.0,
                max: 6.0,
                divisions: 36,
                semanticLabel: context.l10n.trackVolumeOffset,
                onChanged: (val) {
                  currentSliderVol = val;
                  setLocalState(() {});
                },
                onChangeEnd: (val) async {
                  final clamped = val.abs() < 0.2 ? 0.0 : val;
                  currentSliderVol = clamped;
                  await volStore.setGainDbForTrack(trackKey, clamped);
                  playerCubit?.setSongVolumeOverride(song.id, clamped);
                  setLocalState(() {});
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              Divider(color: p.hairline, height: 1),
              const SizedBox(height: AppSpacing.xs),

              // Per-Track BPM (feeds BPM-synced crossfade)
              InkWell(
                onTap: () => _showBpmDialog(
                    context, bpmStore, playerCubit, currentBpm,
                    onSaved: setLocalState),
                borderRadius: BorderRadius.circular(AppRadii.r8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.trackBpm,
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w700,
                          color: p.textSecondary,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentBpm == null
                                ? context.l10n.browseNotSet
                                : '${currentBpm.toStringAsFixed(0)} BPM',
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w700,
                              color: currentBpm == null
                                  ? p.textSecondary
                                  : p.accent,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          Icon(Icons.edit_rounded,
                              size: 14, color: p.textTertiary),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// F-28 (save DSP snapshot) + F-57 (per-track bookmark controls).
  Widget _buildPlaybackToolsSection(BuildContext context, PulsrPalette p) {
    PlayerCubit? playerCubit;
    try {
      playerCubit = context.read<PlayerCubit>();
    } catch (_) {}
    if (playerCubit == null) return const SizedBox.shrink();
    final cubit = playerCubit;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.s10),
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.r16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.playbackTools,
            style: TextStyle(
              fontSize: AppFontSize.label,
              fontWeight: FontWeight.w700,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // F-28: manual DSP snapshot save for the current album.
          InkWell(
            onTap: () async {
              await cubit.saveDspSnapshot();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.dspSavedAlbum)),
              );
            },
            borderRadius: BorderRadius.circular(AppRadii.r8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.l10n.saveDspAlbum,
                    style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary),
                  ),
                  Icon(Icons.save_outlined, size: 18, color: p.accent),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Divider(color: p.hairline, height: 1),
          const SizedBox(height: AppSpacing.s6),
          // F-57: bookmark controls for the currently playing track.
          _buildBookmarkRow(context, p, cubit),
        ],
      ),
    );
  }

  Widget _buildBookmarkRow(BuildContext context, PulsrPalette p, PlayerCubit cubit) {
    final current = cubit.state.currentSong;
    if (current == null || current.id != song.id) {
      return Text(context.l10n.bookmarkHint,
        style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
      );
    }

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final stored = cubit.storedBookmarkFor(song);
        final storedLabel = stored == null
            ? context.l10n.notSetLabel
            : Formatters.formatDuration(
                Duration(milliseconds: stored.positionMs));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.l10n.bookmarkLabel,
                  style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                      color: p.textSecondary),
                ),
                Text(
                  stored == null
                      ? storedLabel
                      : context.l10n.resumeAtTpl(storedLabel),
                  style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                      color: stored == null ? p.textSecondary : p.accent),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (stored != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.accent,
                      side:
                          BorderSide(color: p.accent.withValues(alpha: 0.4)),
                    ),
                    onPressed: () async {
                      await cubit.seek(
                          Duration(milliseconds: stored.positionMs));
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: Text(context.l10n.resumeAction),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.textPrimary,
                    side: BorderSide(color: p.hairline),
                  ),
                  onPressed: () async {
                    final saved = await cubit.saveBookmark();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(saved
                          ? context.l10n.bookmarkSaved
                          : context.l10n.bookmarkEarly),
                    ));
                    setLocalState(() {});
                  },
                  icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: Text(context.l10n.save),
                ),
                if (stored != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.textPrimary,
                      side: BorderSide(color: p.hairline),
                    ),
                    onPressed: () async {
                      await cubit.clearBookmark();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.bookmarkCleared)),
                      );
                      setLocalState(() {});
                    },
                    icon:
                        const Icon(Icons.bookmark_remove_outlined, size: 16),
                    label: Text(context.l10n.clear),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBpmDialog(
    BuildContext context,
    BpmOverrideStore bpmStore,
    PlayerCubit? playerCubit,
    double? currentBpm, {
    required void Function(VoidCallback) onSaved,
  }) async {
    // null = cancel, '' = clear override, otherwise the BPM text to save.
    final result = await PulsrDialogHelper.showCustomDialog<String?>(
      context,
      builder: (_) => _BpmOverrideDialog(currentBpm: currentBpm),
    );
    if (result == null || !context.mounted) return;
    // Clear, or save the validated text returned by the dialog.
    await _persistBpmChoice(
        context, bpmStore, playerCubit, result.isEmpty ? null : result);
    onSaved(() {});
  }

  Future<void> _persistBpmChoice(
    BuildContext context,
    BpmOverrideStore bpmStore,
    PlayerCubit? playerCubit,
    String? raw,
  ) async {
    double? bpm;
    if (raw != null) {
      bpm = double.tryParse(raw);
      if (bpm == null ||
          !bpm.isFinite ||
          bpm < BpmOverrideStore.minBpm ||
          bpm > BpmOverrideStore.maxBpm) {
        return;
      }
    }
    await bpmStore.setBpmForTrack(song.id.toString(), bpm);
    await playerCubit?.setTrackBpm(song, bpm);
    if (context.mounted && bpm == null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.bpmCleared)),
      );
    }
  }

  /// Resolves the stored override to a dropdown value. Returns null
  /// ("Default") when the named preset no longer exists, since
  /// DropdownButton throws on unmatched values.
  String? _eqDropdownValue(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    final lower = stored.toLowerCase();
    if (EqPreset.defaultPresets
        .any((d) => d.name.toLowerCase() == lower)) {
      return stored;
    }
    try {
      if (HeadphoneProfilesRepository()
          .profiles
          .any((hp) => hp.name.toLowerCase() == lower)) {
        return stored;
      }
    } catch (_) {}
    return null;
  }

  Widget _buildInfoRow(String label, String value, PulsrPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.bodySmall,
                  fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.bodySmall,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _BpmOverrideDialog extends StatefulWidget {
  final double? currentBpm;

  const _BpmOverrideDialog({this.currentBpm});

  @override
  State<_BpmOverrideDialog> createState() => _BpmOverrideDialogState();
}

class _BpmOverrideDialogState extends State<_BpmOverrideDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentBpm?.toStringAsFixed(0) ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      Navigator.of(context, rootNavigator: true)
          .pop(widget.currentBpm != null ? '' : null);
      return;
    }
    final bpm = double.tryParse(raw);
    if (bpm == null ||
        !bpm.isFinite ||
        bpm < BpmOverrideStore.minBpm ||
        bpm > BpmOverrideStore.maxBpm) {
      setState(() {
        _error = context.l10n.browseEnterBpmRange;
      });
      return;
    }
    Navigator.of(context, rootNavigator: true).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulsrDialog(
      icon: Icon(Icons.speed_rounded, color: p.accent, size: 28),
      title: Text(context.l10n.trackBpm),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.bpmXfadeDesc,
              style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: p.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g. 128',
                hintStyle: TextStyle(color: p.textTertiary),
                errorText: _error,
                filled: true,
                fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
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
                  borderSide: BorderSide(color: p.accent, width: 1.5),
                ),
              ),
              onChanged: (_) {
                if (_error != null) {
                  setState(() => _error = null);
                }
              },
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.currentBpm != null)
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(''),
            child: Text(context.l10n.clear),
          ),
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
          style: TextButton.styleFrom(
            foregroundColor: p.textSecondary,
          ),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.r12),
            ),
          ),
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}

