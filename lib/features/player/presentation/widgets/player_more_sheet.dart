import 'dart:async' show FutureOr;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/gestures_sheet.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_list_tile.dart';
import '../../../../core/widgets/pulsr_switch.dart';
import '../../../../data/db/app_database.dart';
import '../../../party/presentation/party_sheet.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../cubit/player_cubit.dart';
import '../../../../core/services/ambient_sound_service.dart';
import 'ambient_sound_panel.dart' show iconForEffect;
import 'ambient_sound_sheet.dart';
import 'quran_mode_sheet.dart';

enum _PlayerMoreAction {
  addToPlaylist,
  party,
  quranMode,
  ambientSound,
  gestures,
}

/// Secondary player actions kept out of the primary transport dock.
class PlayerMoreSheet extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;
  final bool popWithResult;

  const PlayerMoreSheet({
    super.key,
    required this.song,
    required this.activeColor,
    this.popWithResult = false,
  });

  static Future<void> show(
    BuildContext context, {
    SongsTableData? song,
    required Color activeColor,
  }) async {
    final playerCubit = context.read<PlayerCubit>();
    final settingsCubit = context.read<SettingsCubit>();
    final action = await PulsrSheetHelper.showPulsrSheet<_PlayerMoreAction>(
      context: context,
      wrapWithContainer: true,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: playerCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: PlayerMoreSheet(
          song: song,
          activeColor: activeColor,
          popWithResult: true,
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _PlayerMoreAction.addToPlaylist:
        if (song != null) {
          await AddToPlaylistSheet.show(context, song: song);
        }
      case _PlayerMoreAction.party:
        await PartySheet.show(context);
      case _PlayerMoreAction.quranMode:
        await QuranModeSheet.show(context);
      case _PlayerMoreAction.ambientSound:
        await AmbientSoundSheet.show(context);
      case _PlayerMoreAction.gestures:
        await GesturesSheet.show(context);
    }
  }

  void _triggerSecondarySheet(
    BuildContext context,
    _PlayerMoreAction action,
    FutureOr<void> Function(BuildContext callerContext) launchFromCaller,
  ) {
    PulsrHaptics.selection();
    if (popWithResult) {
      Navigator.of(context).pop(action);
      return;
    }
    final callerContext = Navigator.of(context).context;
    Navigator.of(context).pop();
    if (callerContext.mounted) {
      launchFromCaller(callerContext);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final isQuranMode = context.select<PlayerCubit, bool>(
      (c) => c.state.isQuranModeEnabled,
    );
    final canvasEnabled = context.select<SettingsCubit, bool>(
      (c) => c.state.canvasEnabled,
    );

    return PulsrBottomSheetContainer(
      title: Text(l10n.moreOptions),
      subtitle: song == null
          ? null
          : Text(
              song!.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (song != null)
              _MoreActionTile(
                icon: Icons.playlist_add_rounded,
                iconColor: activeColor,
                title: l10n.addToPlaylist,
                onTap: () => _triggerSecondarySheet(
                  context,
                  _PlayerMoreAction.addToPlaylist,
                  (callerContext) =>
                      AddToPlaylistSheet.show(callerContext, song: song!),
                ),
              ),
            _MoreActionTile(
              icon: Icons.group_rounded,
              iconColor: p.info,
              title: l10n.partyListenTogether,
              subtitle: l10n.partySyncDescription,
              onTap: () => _triggerSecondarySheet(
                context,
                _PlayerMoreAction.party,
                PartySheet.show,
              ),
            ),
            _MoreActionTile(
              icon: Icons.menu_book_rounded,
              iconColor: activeColor,
              title: l10n.quranMode,
              subtitle:
                  isQuranMode ? l10n.dspQuranModeOn : l10n.dspQuranModeOff,
              isActive: isQuranMode,
              onTap: () => _triggerSecondarySheet(
                context,
                _PlayerMoreAction.quranMode,
                QuranModeSheet.show,
              ),
            ),
            AnimatedBuilder(
              animation: AmbientSoundService(),
              builder: (context, _) {
                final ambient = AmbientSoundService();
                final isAmbientActive = ambient.isEnabled;
                final activeEffects = ambient.activeEffects;
                // Build subtitle: list active effect emojis + paused state
                final subtitle = isAmbientActive
                    ? '${activeEffects.map((e) => e.emoji).join(' ')} • ${l10n.dspEffectsCount(activeEffects.length)}${ambient.isAudioPlaying ? '' : ' ${l10n.dspEffectsPausedSuffix}'}'
                    : l10n.ambientSoundsDesc;
                // Icon: use icon of first active effect, or generic waves
                final firstEffect = activeEffects.firstOrNull;
                final icon = (isAmbientActive && firstEffect != null)
                    ? iconForEffect(firstEffect)
                    : Icons.waves_rounded;
                return _MoreActionTile(
                  icon: icon,
                  iconColor: activeColor,
                  title: l10n.ambientSounds,
                  subtitle: subtitle,
                  isActive: isAmbientActive,
                  onTap: () => _triggerSecondarySheet(
                    context,
                    _PlayerMoreAction.ambientSound,
                    AmbientSoundSheet.show,
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppRadii.r16All,
                  border: Border.all(
                    color: canvasEnabled
                        ? activeColor.withValues(alpha: 0.32)
                        : (p.isHighContrast ? p.borderStrong : p.hairline),
                    width: 1.0,
                  ),
                ),
                child: PulsrListTile(
                  leading: _MoreIcon(
                    icon: Icons.motion_photos_on_rounded,
                    color: activeColor,
                    isActive: canvasEnabled,
                  ),
                  title: l10n.canvasEffects,
                  subtitle: l10n.canvasEffectsSubtitle,
                  tileColor: canvasEnabled
                      ? Color.alphaBlend(
                          activeColor.withValues(alpha: p.isDark ? 0.08 : 0.05),
                          p.surfaceContainer.withValues(alpha: 0.75),
                        )
                      : p.surfaceContainer.withValues(alpha: 0.55),
                  onTap: () {
                    PulsrHaptics.selection();
                    context
                        .read<SettingsCubit>()
                        .toggleCanvasEnabled(!canvasEnabled);
                  },
                  trailing: PulsrSwitch(
                    value: canvasEnabled,
                    activeColor: activeColor,
                    onChanged: (value) {
                      PulsrHaptics.selection();
                      context.read<SettingsCubit>().toggleCanvasEnabled(value);
                    },
                  ),
                ),
              ),
            ),
            _MoreActionTile(
              icon: Icons.gesture_rounded,
              iconColor: activeColor,
              title: l10n.gesturesGuideTitle,
              subtitle: l10n.gesturesGuideSubtitleShort,
              onTap: () => _triggerSecondarySheet(
                context,
                _PlayerMoreAction.gestures,
                GesturesSheet.show,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool isActive;
  final VoidCallback onTap;

  const _MoreActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadii.r16All,
          border: Border.all(
            color: isActive
                ? iconColor.withValues(alpha: 0.35)
                : (p.isHighContrast ? p.borderStrong : p.hairline),
            width: 1.0,
          ),
        ),
        child: PulsrListTile(
          leading: _MoreIcon(
            icon: icon,
            color: iconColor,
            isActive: isActive,
          ),
          title: title,
          subtitle: subtitle,
          tileColor: isActive
              ? Color.alphaBlend(
                  iconColor.withValues(alpha: p.isDark ? 0.08 : 0.05),
                  p.surfaceContainer.withValues(alpha: 0.75),
                )
              : p.surfaceContainer.withValues(alpha: 0.55),
          onTap: onTap,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor,
                    boxShadow: [
                      BoxShadow(
                        color: iconColor.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.surfaceContainerHigh.withValues(alpha: 0.7),
                  border: Border.all(
                    color: p.isHighContrast ? p.borderStrong : p.hairline,
                    width: 0.75,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: isActive ? iconColor : p.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isActive;

  const _MoreIcon({
    required this.icon,
    required this.color,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            color.withValues(alpha: isActive ? 0.26 : 0.18),
            color.withValues(alpha: isActive ? 0.14 : 0.08),
          ],
        ),
        borderRadius: AppRadii.r12All,
        border: Border.all(
          color: color.withValues(alpha: isActive ? 0.45 : 0.24),
          width: 1.0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.20),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: AppIconSize.md,
        color: color,
      ),
    );
  }
}
