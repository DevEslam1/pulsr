// lib/features/tag_editor/tag_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants/app_colors.dart';
import '../../core/di/injection.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import 'artwork_picker.dart';
import 'tag_editor_cubit.dart';
import 'tag_editor_state.dart';
import 'tag_field_widget.dart';

class TagEditorScreen extends StatelessWidget {
  final SongsTableData song;

  const TagEditorScreen({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TagEditorCubit(
        song: song,
        scannerService: getIt<MediaScannerService>(),
      ),
      child: const _TagEditorView(),
    );
  }
}

class _TagEditorView extends StatelessWidget {
  const _TagEditorView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TagEditorCubit, TagEditorState>(
      listener: (context, state) {
        if (state.status == TagEditorStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audio tags updated successfully'),
              backgroundColor: AppColors.primary,
            ),
          );
          Navigator.of(context).pop(true);
        } else if (state.status == TagEditorStatus.failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage ?? 'Failed to update tags'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<TagEditorCubit>();
        final isSaving = state.status == TagEditorStatus.saving;
        final isLoading = state.status == TagEditorStatus.loading;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Edit Tags',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => cubit.saveTags(),
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ArtworkPicker(
                            songId: state.song.id,
                            newArtworkPath: state.newArtworkPath,
                            artworkBytes: state.artworkBytes,
                            removeArtwork: state.removeArtwork,
                            onPick: () => cubit.pickArtwork(),
                            onRemove: () => cubit.removeArtworkImage(),
                          ),
                          const SizedBox(height: 24),
                          TagFieldWidget(
                            label: 'Title',
                            initialValue: state.title,
                            icon: Icons.title_rounded,
                            onChanged: cubit.updateTitle,
                          ),
                          TagFieldWidget(
                            label: 'Artist',
                            initialValue: state.artist,
                            icon: Icons.person_outline_rounded,
                            onChanged: cubit.updateArtist,
                          ),
                          TagFieldWidget(
                            label: 'Album',
                            initialValue: state.album,
                            icon: Icons.album_outlined,
                            onChanged: cubit.updateAlbum,
                          ),
                          TagFieldWidget(
                            label: 'Genre',
                            initialValue: state.genre,
                            icon: Icons.category_outlined,
                            onChanged: cubit.updateGenre,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TagFieldWidget(
                                  label: 'Year',
                                  initialValue: state.year,
                                  icon: Icons.calendar_today_outlined,
                                  keyboardType: TextInputType.number,
                                  onChanged: cubit.updateYear,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TagFieldWidget(
                                  label: 'Track #',
                                  initialValue: state.trackNumber,
                                  icon: Icons.format_list_numbered_rounded,
                                  keyboardType: TextInputType.number,
                                  onChanged: cubit.updateTrackNumber,
                                ),
                              ),
                            ],
                          ),
                          TagFieldWidget(
                            label: 'Comment',
                            initialValue: state.comment,
                            icon: Icons.comment_outlined,
                            onChanged: cubit.updateComment,
                          ),
                          TagFieldWidget(
                            label: 'Lyrics',
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
                        child: const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        ),
                      ),
                  ],
                ),
        );
      }
    );
  }
}
