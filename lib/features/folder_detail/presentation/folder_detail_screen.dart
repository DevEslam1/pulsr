// lib/features/folder_detail/presentation/folder_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/failures.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../library/cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class FolderDetailScreen extends StatefulWidget {
  final FolderItem folder;
  final FolderUseCases? folderUseCases;

  const FolderDetailScreen({
    super.key,
    required this.folder,
    this.folderUseCases,
  });

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  late final FolderUseCases _useCase;
  late bool _isExcluded;

  @override
  void initState() {
    super.initState();
    _useCase = widget.folderUseCases ?? getIt<FolderUseCases>();
    _isExcluded = widget.folder.isExcluded;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final folder = widget.folder;

    return PulsrPagePopScope(
      child: Scaffold(
        appBar: AppBar(
          leading: const PulsrBackButton(),
          title: Text(folder.name),
        actions: [
          IconButton(
            icon: Icon(
              _isExcluded
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: _isExcluded ? p.error : p.textSecondary,
            ),
            tooltip: _isExcluded
                ? context.l10n.browseIncludeInScan
                : context.l10n.browseExcludeFromScan,
            onPressed: () async {
              final newExcluded = !_isExcluded;
              setState(() => _isExcluded = newExcluded);
              LibraryCubit? libraryCubit;
              try {
                libraryCubit = context.read<LibraryCubit>();
              } catch (_) {}
              // Route through LibraryCubit so the songs stream is re-subscribed
              // with the new exclusion. Toggling the raw use case only refreshed
              // the folder list, leaving excluded songs visible in the Library.
              if (libraryCubit != null) {
                await libraryCubit.toggleFolderExclusion(folder.path);
              } else {
                await _useCase.toggleExcludeFolder(folder.path);
              }
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    newExcluded
                        ? context.l10n.folderExcluded
                        : context.l10n.folderIncluded,
                  ),
                  action: SnackBarAction(
                    label: context.l10n.undo,
                    onPressed: () async {
                      if (mounted) setState(() => _isExcluded = !newExcluded);
                      if (libraryCubit != null) {
                        await libraryCubit.toggleFolderExclusion(folder.path);
                      } else {
                        await _useCase.toggleExcludeFolder(folder.path);
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<Result<List<SongsTableData>>>(
        stream: _useCase.watchFolderSongs(folder.path).distinct(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(
                padding: EdgeInsets.only(top: AppSpacing.xs));
          }
          final loadFailed = snapshot.hasError ||
              (snapshot.data?.fold((l) => true, (_) => false) ?? false);
          if (loadFailed) {
            return EmptyStateWidget(
              icon: Icons.error_outline_rounded,
              iconColor: p.error,
              title: context.l10n.couldNotLoadFolderSongs,
              subtitle: context.l10n.libraryReadError,
              primaryActionLabel: context.l10n.retry,
              primaryActionIcon: Icons.refresh_rounded,
              onPrimaryAction: () => setState(() {}),
            );
          }

          final songs =
              snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

          return Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.scrollBottom),
                children: [
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: p.accentContainer,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.hairline),
                        boxShadow: [
                          BoxShadow(
                            color: p.glow,
                            blurRadius: 24,
                            spreadRadius: -4,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isExcluded
                            ? Icons.folder_off_rounded
                            : Icons.folder_rounded,
                        size: 48,
                        color: _isExcluded ? p.error : p.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: Text(
                        folder.name,
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                      child: Text(
                        folder.path,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.label),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  Center(
                    child: Text(
                      Formatters.formatTrackCount(songs.length),
                      style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.bodySmall,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s20),

                  // Action Buttons (Play All, Shuffle)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: songs.isNotEmpty
                                ? () => context
                                    .read<PlayerCubit>()
                                    .playSong(songs.first, queue: songs)
                                : null,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(context.l10n.playAll),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: songs.isNotEmpty
                                ? () {
                                    final shuffled =
                                        List<SongsTableData>.from(songs)
                                          ..shuffle();
                                    context.read<PlayerCubit>().playSong(
                                        shuffled.first,
                                        queue: shuffled);
                                  }
                                : null,
                            icon: Icon(Icons.shuffle_rounded, color: p.accent),
                            label: Text(context.l10n.shuffle),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s20),

                  // Songs List
                  if (songs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: EmptyStateWidget(
                        icon: Icons.music_off_rounded,
                        title: context.l10n.browseNoTracksFound,
                        subtitle: context.l10n.browseNoTracksInFolder,
                      ),
                    )
                  else
                    for (int i = 0; i < songs.length; i++)
                      SongTile(
                        song: songs[i],
                        index: i,
                        subtitleOverride:
                            '${songs[i].artist} • ${songs[i].album}',
                        onTap: () => context
                            .read<PlayerCubit>()
                            .playSong(songs[i], queue: songs),
                        onMorePressed: () => SongInfoSheet.show(context, song: songs[i]),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
}
