// lib/features/tag_editor/tag_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/di/injection.dart';
import '../../core/services/metadata_search_service.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import 'artwork_picker.dart';
import 'tag_editor_cubit.dart';
import 'tag_editor_state.dart';
import 'tag_field_widget.dart';

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

class _TagEditorView extends StatelessWidget {
  const _TagEditorView();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BlocConsumer<TagEditorCubit, TagEditorState>(
      listener: (context, state) {
        if (state.status == TagEditorStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.isBatchMode ? 'Updated ${state.batchSongs.length} tracks successfully!' : context.l10n.tagsSavedSuccess),
              backgroundColor: context.palette.accent,
            ),
          );
          Navigator.of(context).pop(true);
        } else if (state.status == TagEditorStatus.failure || state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage ?? context.l10n.tagsSaveError),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<TagEditorCubit>();
        final isSaving = state.status == TagEditorStatus.saving;
        final isLoading = state.status == TagEditorStatus.loading;
        final isAutoFetching = state.isAutoFetching;

        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            backgroundColor: p.bg,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              state.isBatchMode ? 'Batch Edit (${state.batchSongs.length} Tracks)' : context.l10n.tagEditor,
              style: TextStyle(
                color: p.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            actions: [
              TextButton(
                onPressed: (isSaving || isAutoFetching) ? null : () => cubit.saveTags(),
                child: isSaving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
                      )
                    : Text(
                        context.l10n.save,
                        style: TextStyle(
                          color: p.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: isLoading
              ? Center(child: CircularProgressIndicator(color: p.accent))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Stack(
                      children: [
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (state.isBatchMode)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: p.accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: p.accent.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.checklist_rounded, color: p.accent, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Batch editing ${state.batchSongs.length} tracks. Common tags and cover art will be updated on all selected files.',
                                          style: TextStyle(fontSize: 12, color: p.textPrimary, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ArtworkPicker(
                                songId: state.song.id,
                                newArtworkPath: state.newArtworkPath,
                                artworkBytes: state.artworkBytes,
                                removeArtwork: state.removeArtwork,
                                onPick: () => cubit.pickArtwork(),
                                onRemove: () => cubit.removeArtworkImage(),
                              ),
                              const SizedBox(height: 16),
                              if (!state.isBatchMode) ...[
                                Center(
                                  child: OutlinedButton.icon(
                                    onPressed: (isAutoFetching || isSaving)
                                        ? null
                                        : () async {
                                            final ok = await cubit.autoFetchOnlineTags();
                                            if (ok && context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: const Text('Online metadata retrieved successfully!'),
                                                  backgroundColor: p.accent,
                                                ),
                                              );
                                            }
                                          },
                                    icon: isAutoFetching
                                        ? SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
                                          )
                                        : Icon(Icons.auto_awesome_rounded, size: 18, color: p.accent),
                                    label: Text(
                                      isAutoFetching ? 'Searching Online Metadata...' : 'Auto-Fetch Tags & Cover Art',
                                      style: TextStyle(
                                        color: p.accent,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                TagFieldWidget(
                                  label: context.l10n.songTitle,
                                  initialValue: state.title,
                                  icon: Icons.title_rounded,
                                  onChanged: cubit.updateTitle,
                                ),
                              ],
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
                                    const SizedBox(width: 12),
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
                              TagFieldWidget(
                                label: 'Comment',
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
                                  hintText: 'Enter song lyrics...',
                                  onChanged: cubit.updateLyrics,
                                ),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                        if (isSaving)
                          Container(
                            color: Colors.black45,
                            child: Center(
                              child: CircularProgressIndicator(color: p.accent),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
