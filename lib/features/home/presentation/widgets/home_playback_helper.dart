// lib/features/home/presentation/widgets/home_playback_helper.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/db/app_database.dart';
import '../../../../domain/usecases/get_songs_usecase.dart';
import '../../../library/cubit/library_cubit.dart';
import '../../../player/cubit/player_cubit.dart';

/// Builds a seamless playback queue combining section tracks with the rest
/// of the user's library so playback never abruptly pauses when a short
/// section finishes.
List<SongsTableData> buildQueueWithLibraryFallback({
  required List<SongsTableData> sectionSongs,
  required List<SongsTableData> librarySongs,
}) {
  if (librarySongs.isEmpty) return sectionSongs;
  final existingIds = sectionSongs.map((s) => s.id).toSet();
  final remaining = librarySongs.where((s) => !existingIds.contains(s.id));
  return [...sectionSongs, ...remaining];
}

/// Plays [song] starting with [sectionSongs] followed by the remaining
/// songs in the user's library, ensuring continuous playback without stopping.
Future<void> playSongWithLibraryFallback({
  required BuildContext context,
  required PlayerCubit playerCubit,
  required SongsTableData song,
  required List<SongsTableData> sectionSongs,
  GetSongsUseCase? getSongsUseCase,
}) async {
  var librarySongs = context.read<LibraryCubit?>()?.state.songs ?? const [];
  if (librarySongs.isEmpty && getSongsUseCase != null) {
    final res = await getSongsUseCase.getAllSongs();
    librarySongs = res.fold((_) => const [], (r) => r);
  }

  final effectiveQueue = buildQueueWithLibraryFallback(
    sectionSongs: sectionSongs,
    librarySongs: librarySongs,
  );

  await playerCubit.playSong(song, queue: effectiveQueue);
}
