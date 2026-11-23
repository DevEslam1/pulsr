part of 'search_screen.dart';

// ==================== SUGGESTIONS OVERLAY ====================
class _SuggestionsCard extends StatelessWidget {
  final String query;
  final List<String> suggestions;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onFill;

  const _SuggestionsCard({
    required this.query,
    required this.suggestions,
    required this.onSelect,
    required this.onFill,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final baseStyle = TextStyle(
      color: p.textPrimary,
      fontSize: AppFontSize.body,
      fontWeight: FontWeight.w500,
    );
    final matchStyle = TextStyle(
      color: p.accent,
      fontSize: AppFontSize.body,
      fontWeight: FontWeight.w800,
    );

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.scrimAt(p.isDark ? 0.45 : 0.16),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                (MediaQuery.sizeOf(context).height * 0.42).clamp(160.0, 320.0),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < suggestions.length; i++) ...[
              if (i > 0) Divider(color: p.hairline, height: 1),
              Semantics(
                button: true,
                label: suggestions[i],
                child: InkWell(
                  onTap: () => onSelect(suggestions[i]),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSpacing.minTouchTarget,
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AppSpacing.sm,
                        end: AppSpacing.xxs,
                        top: AppSpacing.xxs,
                        bottom: AppSpacing.xxs,
                      ),
                      child: Row(
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              Icons.search_rounded,
                              color: p.textTertiary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: PulsrHighlightedText(
                              text: suggestions[i],
                              query: query,
                              baseStyle: baseStyle,
                              matchStyle: matchStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            constraints: const BoxConstraints(
                              minWidth: AppSpacing.minTouchTarget,
                              minHeight: AppSpacing.minTouchTarget,
                            ),
                            tooltip: context.l10n.search,
                            icon: Icon(
                              Icons.north_west_rounded,
                              size: 17,
                              color: p.textTertiary,
                            ),
                            onPressed: () => onFill(suggestions[i]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== START PAGE (empty query) ====================
class _StartPage extends StatelessWidget {
  final List<String> history;
  final bool showOnline;
  final int tab;
  final ValueChanged<String> onRecent;
  final ValueChanged<String> onFillQuery;
  final ValueChanged<String> onTag;
  final ValueChanged<String> onSaved;

  const _StartPage({
    required this.history,
    required this.showOnline,
    required this.tab,
    required this.onRecent,
    required this.onFillQuery,
    required this.onTag,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ytm = showOnline ? context.read<YtmSearchCubit?>() : null;
    final local = context.read<SearchCubit?>();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsetsDirectional.fromSTEB(
        Adaptive.pagePadding(context),
        AppSpacing.sm,
        Adaptive.pagePadding(context),
        PulsrLayoutMetrics.scrollBottom(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRecentSearchesSection(context, p, local, ytm),
          if (tab != 2 && local != null)
            ValueListenableBuilder<List<String>>(
              valueListenable: local.savedSearches,
              builder: (context, saved, _) {
                if (saved.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitleRow(
                      icon: Icons.bookmarks_rounded,
                      title: context.l10n.savedSearches,
                      p: p,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final entry in saved)
                          _SavedSearchChip(
                            entry: entry,
                            palette: p,
                            onTap: () => onSaved(entry),
                            onDelete: () {
                              PulsrHaptics.lightImpact();
                              local.removeSavedSearch(entry);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                );
              },
            ),
          if (tab != 2 && local != null)
            ValueListenableBuilder<List<SongsTableData>>(
              valueListenable: local.searchPlayedSongs,
              builder: (context, playedSongs, _) {
                if (playedSongs.isEmpty) return const SizedBox.shrink();
                final currentSongId = context
                    .select<PlayerCubit, int?>((c) => c.state.currentSong?.id);
                final player = context.read<PlayerCubit>();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRecentSectionHeader(
                      context: context,
                      icon: Icons.history_toggle_off_rounded,
                      title: context.l10n.recentlyPlayed,
                      onClear: () {
                        PulsrHaptics.lightImpact();
                        local.clearSearchPlayedSongs();
                      },
                      p: p,
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: p.surfaceContainer.withValues(alpha: 0.45),
                        borderRadius: AppRadii.r16All,
                        border: Border.all(color: p.hairline),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0;
                              i < playedSongs.take(6).length;
                              i++) ...[
                            if (i > 0)
                              Divider(
                                color: p.hairline,
                                height: 1,
                                indent: 68,
                              ),
                            _SearchPlayedSongTile(
                              song: playedSongs[i],
                              isCurrent: currentSongId == playedSongs[i].id,
                              onTap: () {
                                PulsrHaptics.selectionClick();
                                local.recordPlayedSong(playedSongs[i]);
                                player.playSong(
                                  playedSongs[i],
                                  queue: playedSongs,
                                );
                              },
                              onRemove: () => local
                                  .removeSearchPlayedSong(playedSongs[i].id),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                );
              },
            ),
          if (showOnline && (tab == 0 || tab == 2)) ...[
            _sectionTitleRow(
              icon: Icons.local_fire_department_rounded,
              title: context.l10n.popularSearches,
              p: p,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final tag in _onlineTags)
                  PulsrChip(
                    icon: Icons.trending_up_rounded,
                    label: _localizedTag(context, tag),
                    variant: PulsrChipVariant.action,
                    onTap: () => onTag(tag),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentSearchesSection(
    BuildContext context,
    PulsrPalette p,
    SearchCubit? local,
    YtmSearchCubit? ytm,
  ) {
    if (ytm == null) {
      if (tab == 2 || local == null || history.isEmpty) {
        return const SizedBox.shrink();
      }
      return _buildHistoryCard(
        context: context,
        p: p,
        terms: history.take(6).toList(),
        onClear: () {
          PulsrHaptics.lightImpact();
          local.clearHistory();
        },
        onRemove: (term) => local.removeHistoryQuery(term),
      );
    }

    return ValueListenableBuilder<List<String>>(
      valueListenable: ytm.historyNotifier,
      builder: (context, onlineHistory, _) {
        if (tab == 0) {
          final combined = <String>[];
          final seen = <String>{};
          final maxLen = history.length > onlineHistory.length
              ? history.length
              : onlineHistory.length;
          for (var i = 0; i < maxLen; i++) {
            if (i < history.length) {
              final term = history[i].trim();
              if (term.isNotEmpty && seen.add(term.toLowerCase())) {
                combined.add(history[i]);
              }
            }
            if (i < onlineHistory.length) {
              final term = onlineHistory[i].trim();
              if (term.isNotEmpty && seen.add(term.toLowerCase())) {
                combined.add(onlineHistory[i]);
              }
            }
          }
          if (combined.isEmpty) return const SizedBox.shrink();

          return _buildHistoryCard(
            context: context,
            p: p,
            terms: combined.take(6).toList(),
            onClear: () {
              PulsrHaptics.lightImpact();
              local?.clearHistory();
              ytm.clearHistory();
            },
            onRemove: (term) {
              local?.removeHistoryQuery(term);
              ytm.removeHistoryQuery(term);
            },
          );
        } else if (tab == 1) {
          if (local == null || history.isEmpty) return const SizedBox.shrink();
          return _buildHistoryCard(
            context: context,
            p: p,
            terms: history.take(6).toList(),
            onClear: () {
              PulsrHaptics.lightImpact();
              local.clearHistory();
            },
            onRemove: (term) => local.removeHistoryQuery(term),
          );
        } else {
          if (onlineHistory.isEmpty) return const SizedBox.shrink();
          return _buildHistoryCard(
            context: context,
            p: p,
            terms: onlineHistory.take(6).toList(),
            onClear: () {
              PulsrHaptics.lightImpact();
              ytm.clearHistory();
            },
            onRemove: (term) => ytm.removeHistoryQuery(term),
          );
        }
      },
    );
  }

  Widget _buildHistoryCard({
    required BuildContext context,
    required PulsrPalette p,
    required List<String> terms,
    required VoidCallback onClear,
    required ValueChanged<String> onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRecentSectionHeader(
          context: context,
          icon: Icons.history_rounded,
          title: context.l10n.recentSearches,
          onClear: onClear,
          p: p,
        ),
        Container(
          decoration: BoxDecoration(
            color: p.surfaceContainer.withValues(alpha: 0.45),
            borderRadius: AppRadii.r16All,
            border: Border.all(color: p.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < terms.length; i++) ...[
                if (i > 0) Divider(color: p.hairline, height: 1, indent: 42),
                _RecentRow(
                  icon: Icons.history_rounded,
                  term: terms[i],
                  onTap: () => onRecent(terms[i]),
                  onFill: () => onFillQuery(terms[i]),
                  onRemove: () => onRemove(terms[i]),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _sectionTitleRow({
    required IconData icon,
    required String title,
    required PulsrPalette p,
  }) {
    return Semantics(
      header: true,
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, size: 14, color: p.textTertiary)),
          const SizedBox(width: AppSpacing.s6),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w800,
              color: p.textTertiary,
              letterSpacing: AppTracking.wide,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedSearchChip extends StatelessWidget {
  final String entry;
  final PulsrPalette palette;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SavedSearchChip({
    required this.entry,
    required this.palette,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final decoded = SearchCubit.decodeSavedSearch(entry);
    final hasCustomFilter =
        decoded.filter.isNotEmpty && decoded.filter != 'All';

    return Semantics(
      button: true,
      label: hasCustomFilter
          ? '${decoded.query}, ${decoded.filter}'
          : decoded.query,
      explicitChildNodes: true,
      child: Material(
        color: palette.surfaceContainer,
        borderRadius: AppRadii.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.circular(12),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.s10,
              end: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadii.circular(12),
              border: Border.all(color: palette.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.bookmark_rounded,
                    size: 14,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.s6),
                Flexible(
                  child: Text(
                    decoded.query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (hasCustomFilter) ...[
                  const SizedBox(width: AppSpacing.s6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.14),
                      borderRadius: AppRadii.circular(6),
                    ),
                    child: Text(
                      _localizedFilterLabel(context, decoded.filter),
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  tooltip: context.l10n.remove,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: palette.textTertiary,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchPlayedSongTile extends StatelessWidget {
  final SongsTableData song;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _SearchPlayedSongTile({
    required this.song,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: isCurrent,
      label: context.l10n.songByArtist(song.title, song.artist),
      child: Material(
        color: isCurrent ? p.accent.withValues(alpha: 0.10) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => SongOptionsSheet.show(context, song: song),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10,
                vertical: AppSpacing.s6,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: CachedArtwork(
                      id: song.id,
                      remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                      albumId: song.albumId,
                      type: ArtworkType.AUDIO,
                      size: 44,
                      borderRadius: 10,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent ? p.accent : p.textPrimary,
                            fontSize: AppFontSize.body,
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isCurrent)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: ExcludeSemantics(
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          size: 18,
                          color: p.accent,
                        ),
                      ),
                    ),
                  IconButton(
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: p.textTertiary,
                    ),
                    tooltip: context.l10n.remove,
                    onPressed: onRemove,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final IconData icon;
  final String term;
  final VoidCallback onTap;
  final VoidCallback onFill;
  final VoidCallback onRemove;

  const _RecentRow({
    required this.icon,
    required this.term,
    required this.onTap,
    required this.onFill,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: term,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.sm,
                end: AppSpacing.xxs,
                top: AppSpacing.xxs,
                bottom: AppSpacing.xxs,
              ),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(icon, size: 18, color: p.textTertiary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      term,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: AppFontSize.body,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget,
                    ),
                    tooltip: context.l10n.search,
                    icon: Icon(
                      Icons.north_west_rounded,
                      size: 16,
                      color: p.textTertiary,
                    ),
                    onPressed: onFill,
                  ),
                  IconButton(
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget,
                    ),
                    tooltip: context.l10n.remove,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: p.textTertiary,
                    ),
                    onPressed: onRemove,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
