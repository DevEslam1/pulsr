// lib/features/tag_editor/tag_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/di/injection.dart';
import '../../core/services/metadata_search_service.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/widgets/pulsr_back_button.dart';
import '../../core/widgets/pulsr_bottom_sheet.dart';
import '../../core/widgets/pulsr_page_pop_scope.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import 'artwork_picker.dart';
import 'tag_editor_cubit.dart';
import 'tag_editor_state.dart';
import 'tag_field_widget.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class TagEditorScreen extends StatelessWidget {
  final SongsTableData song;
  final List<SongsTableData>? batchSongs;

  const TagEditorScreen({super.key, required this.song, this.batchSongs});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TagEditorCubit(
        song: song,
        batchSongs: batchSongs,
        scannerService: getIt<MediaScannerService>(),
        metadataSearchService: getIt<MetadataSearchService>(),
      ),
      child: const _TagEditorView(),
    );
  }
}

class _TagEditorView extends StatefulWidget {
  const _TagEditorView();

  @override
  State<_TagEditorView> createState() => _TagEditorViewState();
}

class _TagEditorViewState extends State<_TagEditorView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInterruptedBatch();
    });
  }

  Future<void> _checkInterruptedBatch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final checkpoint = prefs.getStringList(TagEditorCubit.batchCheckpointKey);
      if (checkpoint != null && checkpoint.isNotEmpty && mounted) {
        await prefs.remove(TagEditorCubit.batchCheckpointKey);
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.l10n.partialBatchDetected),
            content: Text(
              '${checkpoint.length} file(s) were not updated due to an interrupted batch.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(context.l10n.ok),
              ),
            ],
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BlocConsumer<TagEditorCubit, TagEditorState>(
      listener: (context, state) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;
        if (state.status == TagEditorStatus.success) {
          messenger
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(state.isBatchMode
                    ? '${context.l10n.browseUpdatedPrefix} ${state.batchSongs.length} ${context.l10n.browseTracksSuccessfully}'
                    : context.l10n.tagsSavedSuccess),
                backgroundColor: p.accent,
              ),
            );
          Navigator.of(context).pop(true);
        } else if (state.status == TagEditorStatus.failure ||
            state.errorMessage != null) {
          messenger
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(state.errorMessage ?? context.l10n.tagsSaveError),
                backgroundColor: p.error,
              ),
            );
        }
      },
      builder: (context, state) {
        final cubit = context.read<TagEditorCubit>();
        final isSaving = state.status == TagEditorStatus.saving;
        final isLoading = state.status == TagEditorStatus.loading;
        final isAutoFetching = state.isAutoFetching;

        return PulsrPagePopScope(
          child: Scaffold(
            backgroundColor: p.bg,
            appBar: _TagEditorAppBar(
              state: state,
              cubit: cubit,
              isSaving: isSaving,
              isAutoFetching: isAutoFetching,
            ),
            body: isLoading
                ? Center(child: CircularProgressIndicator(color: p.accent))
                : _TagEditorBody(
                    state: state,
                    cubit: cubit,
                    isSaving: isSaving,
                    isAutoFetching: isAutoFetching,
                  ),
          ),
        );
      },
    );
  }
}

class _TagEditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _TagEditorAppBar({
    required this.state,
    required this.cubit,
    required this.isSaving,
    required this.isAutoFetching,
  });

  final TagEditorState state;
  final TagEditorCubit cubit;
  final bool isSaving;
  final bool isAutoFetching;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppBar(
      backgroundColor: p.bg,
      elevation: 0,
      leading: const PulsrBackButton(),
      title: Text(
        state.isBatchMode
            ? '${context.l10n.browseBatchEdit} (${state.batchSongs.length} ${context.l10n.browseTracks})'
            : context.l10n.tagEditor,
        style: TextStyle(
          color: p.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: AppFontSize.title,
        ),
      ),
      actions: [
        BlocBuilder<TagEditorCubit, TagEditorState>(
          buildWhen: (a, b) =>
              a.title != b.title ||
              a.artist != b.artist ||
              a.album != b.album ||
              a.genre != b.genre ||
              a.year != b.year ||
              a.trackNumber != b.trackNumber ||
              a.discNumber != b.discNumber,
          builder: (context, _) {
            final canUndo = context.read<TagEditorCubit>().canUndo;
            return IconButton(
              tooltip: context.l10n.undo,
              icon: const Icon(Icons.undo_rounded),
              onPressed:
                  canUndo && !isSaving ? () => cubit.undo() : null,
            );
          },
        ),
        TextButton(
          onPressed:
              (isSaving || isAutoFetching) ? null : () => cubit.saveTags(),
          child: isSaving
              ? SizedBox(
                  width: AppSpacing.s18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: p.accent),
                )
              : Text(
                  context.l10n.save,
                  style: TextStyle(
                    color: p.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.bodyLarge,
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

class _TagEditorBody extends StatelessWidget {
  const _TagEditorBody({
    required this.state,
    required this.cubit,
    required this.isSaving,
    required this.isAutoFetching,
  });

  final TagEditorState state;
  final TagEditorCubit cubit;
  final bool isSaving;
  final bool isAutoFetching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s20, vertical: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (state.isBatchMode)
                    _BatchEditBanner(count: state.batchSongs.length),
                  ArtworkPicker(
                    songId: state.song.id,
                    newArtworkPath: state.newArtworkPath,
                    artworkBytes: state.artworkBytes,
                    removeArtwork: state.removeArtwork,
                    onPick: () => cubit.pickArtwork(),
                    onRemove: () => cubit.removeArtworkImage(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: _AutoFetchButton(
                      state: state,
                      cubit: cubit,
                      isSaving: isSaving,
                      isAutoFetching: isAutoFetching,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  _TagFields(state: state, cubit: cubit),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
            if (isSaving) _SavingOverlay(state: state),
          ],
        ),
      ),
    );
  }
}

class _BatchEditBanner extends StatelessWidget {
  const _BatchEditBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.r12),
        border: Border.all(color: p.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.checklist_rounded, color: p.accent, size: 20),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Text(
              context.l10n.browseBatchEditingBody(count),
              style: TextStyle(
                  fontSize: AppFontSize.label,
                  color: p.textPrimary,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoFetchButton extends StatelessWidget {
  const _AutoFetchButton({
    required this.state,
    required this.cubit,
    required this.isSaving,
    required this.isAutoFetching,
  });

  final TagEditorState state;
  final TagEditorCubit cubit;
  final bool isSaving;
  final bool isAutoFetching;

  Future<void> _run(BuildContext context) async {
    final p = context.palette;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (state.isBatchMode) {
      final resolved = await cubit.autoFetchBatchTags();
      if (!context.mounted) return;
      final message = resolved > 0
          ? 'Online metadata filled for $resolved track${resolved == 1 ? '' : 's'} (shared fields only)'
          : context.l10n.noOnlineMetadata;
      messenger
        ?.clearSnackBars();
      messenger?.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: resolved > 0 ? p.accent : null,
          ),
        );
      return;
    }

    final matches = await cubit.searchOnlineMatches();
    if (!context.mounted) return;
    if (matches.isEmpty) {
      messenger
        ?.clearSnackBars();
      messenger?.showSnackBar(SnackBar(content: Text(context.l10n.noOnlineMetadata)));
      return;
    }

    if (matches.length == 1) {
      final ok = await cubit.applyMetadataResult(matches.first);
      if (ok && context.mounted) {
        messenger
          ?.clearSnackBars();
        messenger?.showSnackBar(SnackBar(
            content: Text(context.l10n.onlineMetadataApplied),
            backgroundColor: p.accent,
          ));
      }
      return;
    }

    final selected =
        await PulsrSheetHelper.showPulsrSheet<OnlineTrackMetadata>(
      context: context,
      builder: (ctx) => _MetadataMatchSheet(matches: matches),
    );

    if (selected != null && context.mounted) {
      final ok = await cubit.applyMetadataResult(selected);
      if (ok && context.mounted) {
        messenger
          ?.clearSnackBars();
        messenger?.showSnackBar(SnackBar(
            content: Text(context.l10n.onlineMetadataApplied),
            backgroundColor: p.accent,
          ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return OutlinedButton.icon(
      onPressed: (isAutoFetching || isSaving) ? null : () => _run(context),
      icon: isAutoFetching
          ? SizedBox(
              width: AppSpacing.md,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
            )
          : Icon(Icons.auto_awesome_rounded, size: 18, color: p.accent),
      label: Text(
        isAutoFetching
            ? context.l10n.browseSearchingOnlineMetadata
            : context.l10n.browseAutoFetchTags,
        style: TextStyle(
          color: p.accent,
          fontWeight: FontWeight.w600,
          fontSize: AppFontSize.body,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.r12),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.s10),
      ),
    );
  }
}

class _MetadataMatchSheet extends StatelessWidget {
  const _MetadataMatchSheet({required this.matches});

  final List<OnlineTrackMetadata> matches;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 8),
            child: Text(
              '${context.l10n.browseSelectBestMatch} (${matches.length})',
              style: TextStyle(
                color: p.textPrimary,
                fontSize: AppFontSize.bodyLarge,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: matches.length,
              separatorBuilder: (_, __) =>
                  Divider(color: p.hairline, height: 1),
              itemBuilder: (ctx, idx) {
                final item = matches[idx];
                return ListTile(
                  leading: item.artworkUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.r8),
                          child: Image.network(
                            item.artworkUrl!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            cacheWidth: 88,
                            cacheHeight: 88,
                            loadingBuilder: (context, child, progress) => progress == null
                                ? child
                                : Container(
                                    width: 44,
                                    height: 44,
                                    color: p.surfaceContainer,
                                    child: Center(
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: p.accent),
                                      ),
                                    ),
                                  ),
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.music_note_rounded,
                                color: p.accent),
                          ),
                        )
                      : Icon(Icons.music_note_rounded, color: p.accent),
                  title: Text(
                    item.title,
                    style: TextStyle(
                        color: p.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${item.artist} • ${item.album}${item.releaseYear != null ? " (${item.releaseYear})" : ""}',
                    style: TextStyle(
                        color: p.textSecondary, fontSize: AppFontSize.label),
                  ),
                  onTap: () => Navigator.of(ctx).pop(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TagFields extends StatelessWidget {
  const _TagFields({required this.state, required this.cubit});

  final TagEditorState state;
  final TagEditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!state.isBatchMode)
          TagFieldWidget(
            label: context.l10n.songTitle,
            initialValue: state.title,
            icon: Icons.title_rounded,
            onChanged: cubit.updateTitle,
          ),
        TagFieldWidget(
          label: context.l10n.artist,
          initialValue: state.artist,
          icon: Icons.person_outline_rounded,
          onChanged: cubit.updateArtist,
        ),
        TagFieldWidget(
          label: context.l10n.album,
          initialValue: state.album,
          icon: Icons.album_outlined,
          onChanged: cubit.updateAlbum,
        ),
        TagFieldWidget(
          label: context.l10n.genre,
          initialValue: state.genre,
          icon: Icons.category_outlined,
          onChanged: cubit.updateGenre,
        ),
        Row(
          children: [
            Expanded(
              child: TagFieldWidget(
                label: context.l10n.year,
                initialValue: state.year,
                icon: Icons.calendar_today_outlined,
                keyboardType: TextInputType.number,
                onChanged: cubit.updateYear,
              ),
            ),
            if (!state.isBatchMode) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TagFieldWidget(
                  label: context.l10n.trackNumber,
                  initialValue: state.trackNumber,
                  icon: Icons.format_list_numbered_rounded,
                  keyboardType: TextInputType.number,
                  onChanged: cubit.updateTrackNumber,
                ),
              ),
            ],
          ],
        ),
        if (!state.isBatchMode)
          TagFieldWidget(
            label: context.l10n.browseDiscNumber,
            initialValue: state.discNumber,
            icon: Icons.album_outlined,
            keyboardType: TextInputType.number,
            hintText: 'e.g. 1',
            onChanged: cubit.updateDiscNumber,
          ),
        TagFieldWidget(
          label: context.l10n.browseComment,
          initialValue: state.comment,
          icon: Icons.comment_outlined,
          onChanged: cubit.updateComment,
        ),
        if (!state.isBatchMode)
          TagFieldWidget(
            label: context.l10n.lyrics,
            initialValue: state.lyrics,
            icon: Icons.lyrics_outlined,
            maxLines: 4,
            hintText: context.l10n.browseEnterLyrics,
            onChanged: cubit.updateLyrics,
          ),
      ],
    );
  }
}

class _SavingOverlay extends StatelessWidget {
  const _SavingOverlay({required this.state});

  final TagEditorState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      color: Colors.black45,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: state.isBatchMode ? state.batchProgress : null,
              color: p.accent,
            ),
            if (state.isBatchMode && state.batchProgress != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${(state.batchProgress! * 100).toInt()}%',
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
