import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_list_tile.dart';
import '../../../../core/widgets/pulsr_switch.dart';
import '../../../../data/db/app_database.dart';
import '../../../party/presentation/party_sheet.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../cubit/player_cubit.dart';
import 'quran_mode_sheet.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

/// Secondary player actions kept out of the primary transport dock.
class PlayerMoreSheet extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;

  const PlayerMoreSheet({
    super.key,
    required this.song,
    required this.activeColor,
  });

  static Future<void> show(
    BuildContext context, {
    SongsTableData? song,
    required Color activeColor,
  }) {
    final playerCubit = context.read<PlayerCubit>();
    final settingsCubit = context.read<SettingsCubit>();
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: playerCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: PlayerMoreSheet(song: song, activeColor: activeColor),
      ),
    );
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
    final hasDownload = song != null &&
        (song!.source == SongSource.youtube ||
            (song!.remoteId != null && song!.remoteId!.isNotEmpty));

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
            if (hasDownload)
              _MoreActionTile(
                icon: Icons.playlist_add_rounded,
                iconColor: activeColor,
                title: l10n.addToPlaylist,
                onTap: () {
                  Navigator.of(context).pop();
                  AddToPlaylistSheet.show(context, song: song!);
                },
              ),
            _MoreActionTile(
              icon: Icons.group_rounded,
              iconColor: AppColors.accentCyan,
              title: l10n.partyListenTogether,
              subtitle: l10n.partySyncDescription,
              onTap: () {
                Navigator.of(context).pop();
                PartySheet.show(context);
              },
            ),
            _MoreActionTile(
              icon: Icons.menu_book_rounded,
              iconColor: activeColor,
              title: l10n.quranMode,
              subtitle:
                  isQuranMode ? l10n.dspQuranModeOn : l10n.dspQuranModeOff,
              onTap: () {
                Navigator.of(context).pop();
                QuranModeSheet.show(context);
              },
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s6),
              child: PulsrListTile(
                leading: _MoreIcon(
                    icon: Icons.motion_photos_on_rounded, color: activeColor),
                title: l10n.canvasEffects,
                subtitle: l10n.canvasEffectsSubtitle,
                tileColor: p.surfaceContainer.withValues(alpha: 0.55),
                onTap: () => context
                    .read<SettingsCubit>()
                    .toggleCanvasEnabled(!canvasEnabled),
                trailing: PulsrSwitch(
                  value: canvasEnabled,
                  activeColor: activeColor,
                  onChanged: (value) =>
                      context.read<SettingsCubit>().toggleCanvasEnabled(value),
                ),
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
  final VoidCallback onTap;

  const _MoreActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s6),
      child: PulsrListTile(
        leading: _MoreIcon(icon: icon, color: iconColor),
        title: title,
        subtitle: subtitle,
        tileColor: p.surfaceContainer.withValues(alpha: 0.55),
        onTap: onTap,
        trailing: Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: p.textTertiary,
        ),
      ),
    );
  }
}

class _MoreIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _MoreIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadii.r12All,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, size: 19, color: color),
    );
  }
}
