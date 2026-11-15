// lib/features/library/presentation/library_tab_sort.dart
import 'package:flutter/material.dart';
import 'package:pulsr/core/utils/l10n_extensions.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/genre_item.dart';
import 'package:pulsr/domain/models/year_item.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import '../../sheets/sort_filter_sheet.dart';

/// Immutable sort state for a single Library tab.
class LibraryTabSortSpec {
  final String sortBy;
  final bool ascending;

  const LibraryTabSortSpec({
    required this.sortBy,
    required this.ascending,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryTabSortSpec &&
          runtimeType == other.runtimeType &&
          sortBy == other.sortBy &&
          ascending == other.ascending;

  @override
  int get hashCode => Object.hash(sortBy, ascending);
}

/// Per-tab sort options, defaults, comparators, and preference keys for
/// non-Songs tabs in `LibraryScreen` (`songs` delegates to `LibraryCubit`).
abstract final class LibraryTabSort {
  static const Map<String, LibraryTabSortSpec> defaults = {
    'downloaded': LibraryTabSortSpec(sortBy: 'title', ascending: true),
    'favorites': LibraryTabSortSpec(sortBy: 'title', ascending: true),
    'albums': LibraryTabSortSpec(sortBy: 'title', ascending: true),
    'artists': LibraryTabSortSpec(sortBy: 'name', ascending: true),
    'folders': LibraryTabSortSpec(sortBy: 'name', ascending: true),
    'genres': LibraryTabSortSpec(sortBy: 'name', ascending: true),
    'years': LibraryTabSortSpec(sortBy: 'year', ascending: false),
  };

  static LibraryTabSortSpec defaultFor(String tabName) =>
      defaults[tabName] ??
      const LibraryTabSortSpec(sortBy: 'title', ascending: true);

  static String sortByPrefKey(String tabName) => 'library_sort_${tabName}_by';
  static String ascendingPrefKey(String tabName) =>
      'library_sort_${tabName}_asc';

  static List<SortOptionSpec> optionsForTab(
    BuildContext context,
    String tabName,
  ) {
    final l10n = context.l10n;
    switch (tabName) {
      case 'downloaded':
        return [
          SortOptionSpec(
            key: 'title',
            label: l10n.title,
            icon: Icons.sort_by_alpha_rounded,
          ),
          SortOptionSpec(
            key: 'artist',
            label: l10n.artist,
            icon: Icons.person_outline_rounded,
          ),
          SortOptionSpec(
            key: 'album',
            label: l10n.albums,
            icon: Icons.album_outlined,
          ),
          SortOptionSpec(
            key: 'dateAdded',
            label: l10n.recentlyAdded,
            icon: Icons.auto_awesome_mosaic_outlined,
          ),
          SortOptionSpec(
            key: 'duration',
            label: l10n.duration,
            icon: Icons.schedule_rounded,
          ),
          SortOptionSpec(
            key: 'fileSize',
            label: l10n.fileSize,
            icon: Icons.sd_storage_outlined,
          ),
        ];
      case 'favorites':
        return [
          SortOptionSpec(
            key: 'title',
            label: l10n.title,
            icon: Icons.sort_by_alpha_rounded,
          ),
          SortOptionSpec(
            key: 'artist',
            label: l10n.artist,
            icon: Icons.person_outline_rounded,
          ),
          SortOptionSpec(
            key: 'album',
            label: l10n.albums,
            icon: Icons.album_outlined,
          ),
          SortOptionSpec(
            key: 'dateAdded',
            label: l10n.recentlyAdded,
            icon: Icons.auto_awesome_mosaic_outlined,
          ),
          SortOptionSpec(
            key: 'duration',
            label: l10n.duration,
            icon: Icons.schedule_rounded,
          ),
          SortOptionSpec(
            key: 'playCount',
            label: l10n.mostPlayed,
            icon: Icons.trending_up_rounded,
          ),
          SortOptionSpec(
            key: 'lastPlayed',
            label: l10n.recentlyPlayed,
            icon: Icons.history_rounded,
          ),
        ];
      case 'albums':
        return [
          SortOptionSpec(
            key: 'title',
            label: l10n.title,
            icon: Icons.sort_by_alpha_rounded,
          ),
          SortOptionSpec(
            key: 'artist',
            label: l10n.artist,
            icon: Icons.person_outline_rounded,
          ),
          SortOptionSpec(
            key: 'songCount',
            label: l10n.songs,
            icon: Icons.numbers_rounded,
          ),
          SortOptionSpec(
            key: 'year',
            label: l10n.year,
            icon: Icons.calendar_today_rounded,
          ),
        ];
      case 'artists':
        return [
          SortOptionSpec(
            key: 'name',
            label: l10n.artist,
            icon: Icons.sort_by_alpha_rounded,
          ),
          SortOptionSpec(
            key: 'albumCount',
            label: l10n.albums,
            icon: Icons.album_outlined,
          ),
          SortOptionSpec(
            key: 'songCount',
            label: l10n.songs,
            icon: Icons.numbers_rounded,
          ),
        ];
      case 'folders':
      case 'genres':
        return [
          SortOptionSpec(
            key: 'name',
            label: l10n.title,
            icon: Icons.sort_by_alpha_rounded,
          ),
          SortOptionSpec(
            key: 'songCount',
            label: l10n.songs,
            icon: Icons.numbers_rounded,
          ),
        ];
      case 'years':
        return [
          SortOptionSpec(
            key: 'year',
            label: l10n.year,
            icon: Icons.calendar_today_rounded,
          ),
          SortOptionSpec(
            key: 'songCount',
            label: l10n.songs,
            icon: Icons.numbers_rounded,
          ),
        ];
      default:
        return [
          SortOptionSpec(
            key: 'title',
            label: l10n.title,
            icon: Icons.sort_by_alpha_rounded,
          ),
        ];
    }
  }

  static String labelForKey(BuildContext context, String sortBy) {
    final l10n = context.l10n;
    switch (sortBy) {
      case 'title':
      case 'name':
        return l10n.title;
      case 'artist':
        return l10n.artist;
      case 'album':
      case 'albumCount':
        return l10n.albums;
      case 'dateAdded':
        return l10n.recentlyAdded;
      case 'duration':
        return l10n.duration;
      case 'playCount':
        return l10n.mostPlayed;
      case 'rating':
        return l10n.browseTopRated;
      case 'lastPlayed':
        return l10n.recentlyPlayed;
      case 'fileSize':
        return l10n.fileSize;
      case 'sampleRate':
        return l10n.sampleRate;
      case 'year':
        return l10n.year;
      case 'songCount':
        return l10n.songs;
      default:
        return l10n.title;
    }
  }

  static int _dir(int cmp, bool ascending) => ascending ? cmp : -cmp;

  static int _cmpText(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  static List<SongsTableData> sortSongs(
    List<SongsTableData> items,
    LibraryTabSortSpec spec,
  ) {
    final out = List<SongsTableData>.of(items);
    out.sort((a, b) {
      int cmp;
      switch (spec.sortBy) {
        case 'artist':
          cmp = _cmpText(a.artist, b.artist);
        case 'album':
          cmp = _cmpText(a.album, b.album);
        case 'dateAdded':
          cmp = (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0);
        case 'duration':
          cmp = a.durationMs.compareTo(b.durationMs);
        case 'playCount':
          cmp = a.playCount.compareTo(b.playCount);
        case 'lastPlayed':
          cmp = (a.lastPlayed ?? 0).compareTo(b.lastPlayed ?? 0);
        case 'fileSize':
          cmp = (a.fileSize ?? 0).compareTo(b.fileSize ?? 0);
        case 'sampleRate':
          cmp = (a.sampleRate ?? 0).compareTo(b.sampleRate ?? 0);
        case 'year':
          cmp = (a.year ?? 0).compareTo(b.year ?? 0);
        case 'title':
        default:
          cmp = _cmpText(a.title, b.title);
      }
      if (cmp != 0) return _dir(cmp, spec.ascending);
      return _cmpText(a.title, b.title);
    });
    return out;
  }

  static List<AlbumsTableData> sortAlbums(
    List<AlbumsTableData> items,
    LibraryTabSortSpec spec,
  ) {
    final out = List<AlbumsTableData>.of(items);
    out.sort((a, b) {
      int cmp;
      switch (spec.sortBy) {
        case 'artist':
          cmp = _cmpText(a.artist, b.artist);
        case 'songCount':
          cmp = a.songCount.compareTo(b.songCount);
        case 'year':
          cmp = (a.year ?? 0).compareTo(b.year ?? 0);
        case 'title':
        default:
          cmp = _cmpText(a.title, b.title);
      }
      if (cmp != 0) return _dir(cmp, spec.ascending);
      return _cmpText(a.title, b.title);
    });
    return out;
  }

  static List<ArtistsTableData> sortArtists(
    List<ArtistsTableData> items,
    LibraryTabSortSpec spec,
  ) {
    final out = List<ArtistsTableData>.of(items);
    out.sort((a, b) {
      int cmp;
      switch (spec.sortBy) {
        case 'albumCount':
          cmp = a.albumCount.compareTo(b.albumCount);
        case 'songCount':
          cmp = a.songCount.compareTo(b.songCount);
        case 'name':
        default:
          cmp = _cmpText(a.name, b.name);
      }
      if (cmp != 0) return _dir(cmp, spec.ascending);
      return _cmpText(a.name, b.name);
    });
    return out;
  }

  static List<FolderItem> sortFolders(
    List<FolderItem> items,
    LibraryTabSortSpec spec,
  ) {
    final out = List<FolderItem>.of(items);
    out.sort((a, b) {
      int cmp;
      switch (spec.sortBy) {
        case 'songCount':
          cmp = a.songCount.compareTo(b.songCount);
        case 'name':
        default:
          cmp = _cmpText(a.name, b.name);
      }
      if (cmp != 0) return _dir(cmp, spec.ascending);
      return _cmpText(a.name, b.name);
    });
    return out;
  }

  static List<GenreItem> sortGenres(
    List<GenreItem> items,
    LibraryTabSortSpec spec,
  ) {
    final out = List<GenreItem>.of(items);
    out.sort((a, b) {
      int cmp;
      switch (spec.sortBy) {
        case 'songCount':
          cmp = a.songCount.compareTo(b.songCount);
        case 'name':
        default:
          cmp = _cmpText(a.name, b.name);
      }
      if (cmp != 0) return _dir(cmp, spec.ascending);
      return _cmpText(a.name, b.name);
    });
    return out;
  }

  static List<YearItem> sortYears(
    List<YearItem> items,
    LibraryTabSortSpec spec,
  ) {
    final out = List<YearItem>.of(items);
    out.sort((a, b) {
      int cmp;
      switch (spec.sortBy) {
        case 'songCount':
          cmp = a.songCount.compareTo(b.songCount);
        case 'year':
        default:
          cmp = a.year.compareTo(b.year);
      }
      if (cmp != 0) return _dir(cmp, spec.ascending);
      return b.year.compareTo(a.year);
    });
    return out;
  }
}
