import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/song_tile.dart';
import '../../player/cubit/player_cubit.dart';
import '../cubit/ytm_download_cubit.dart';
import '../cubit/ytm_search_cubit.dart';
import '../cubit/ytm_search_state.dart';
import 'widgets/ytm_download_button.dart';

class YtmSearchScreen extends StatelessWidget {
  const YtmSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<YtmSearchCubit>()),
        BlocProvider<YtmDownloadCubit>.value(
            value: getIt<YtmDownloadCubit>()),
      ],
      child: const _YtmSearchView(),
    );
  }
}

class _YtmSearchView extends StatefulWidget {
  const _YtmSearchView();

  @override
  State<_YtmSearchView> createState() => _YtmSearchViewState();
}

class _YtmSearchViewState extends State<_YtmSearchView> {
  final TextEditingController _searchController = TextEditingController();
  Future<List<String>>? _historyFuture;
  Timer? _healthTimer;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
    // statusMessage polls YtmService.isBotCoolingDown which lives outside
    // Bloc state — repaint periodically so the cooldown strip appears /
    // clears without requiring another search.
    _healthTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => mounted ? setState(() {}) : null);
  }

  void _refreshHistory() {
    try {
      _historyFuture = context.read<YtmSearchCubit>().getSearchHistory();
    } catch (_) {
      _historyFuture = Future.value(const <String>[]);
    }
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<YtmSearchCubit>();
    final playerCubit = context.read<PlayerCubit>();

    return PulsrPagePopScope(
      child: Scaffold(
        appBar: AppBar(
          leading: const PulsrBackButton(),
          title: Text(context.l10n.browseYouTubeMusic),
        ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: BlocListener<YtmSearchCubit, YtmSearchState>(
              listenWhen: (prev, curr) =>
                  prev.results != curr.results && curr.results.isNotEmpty,
              listener: (_, __) => setState(_refreshHistory),
              child: BlocBuilder<YtmSearchCubit, YtmSearchState>(
              builder: (context, state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          Adaptive.pagePadding(context),
                          12,
                          Adaptive.pagePadding(context),
                          6),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: cubit.onQueryChanged,
                        decoration: InputDecoration(
                          hintText: context.l10n.browseSongsOnYtm,
                          prefixIcon:
                              Icon(Icons.search_rounded, color: p.textTertiary),
                          suffixIcon: state.query.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear_rounded,
                                      color: p.textTertiary),
                                  onPressed: () {
                                    _searchController.clear();
                                    cubit.clearQuery();
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildBody(context, state, cubit, playerCubit, p),
                    ),
                  ],
                );
              },
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildHistory(BuildContext context, PulsrPalette p) {
    final cubit = context.read<YtmSearchCubit>();
    return FutureBuilder<List<String>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        final history = snapshot.data ?? const <String>[];
        if (history.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.travel_explore_rounded,
            title: context.l10n.searchYtm,
            subtitle: context.l10n.browseYtmSearchScreenDesc,
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 160),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.history,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await cubit.clearHistory();
                    if (mounted) setState(_refreshHistory);
                  },
                  child: Text(context.l10n.browseClearHistory),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in history)
                  ActionChip(
                    label: Text(h,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    avatar: Icon(Icons.history_rounded,
                        size: 16, color: p.textTertiary),
                    onPressed: () {
                      _searchController.text = h;
                      cubit.onQueryChanged(h);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.browseYtmSearchScreenDesc,
              style: TextStyle(color: p.textTertiary, fontSize: 12.5),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    YtmSearchState state,
    YtmSearchCubit cubit,
    PlayerCubit playerCubit,
    PulsrPalette p,
  ) {
    if (state.isLoading && state.results.isEmpty) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }

    if (state.errorMessage != null) {
      return EmptyStateWidget(
        icon: Icons.cloud_off_rounded,
        title: context.l10n.browseSearchFailed,
        subtitle: state.errorMessage!,
        primaryActionLabel: context.l10n.tryAgain,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: cubit.retry,
      );
    }

    if (state.results.isEmpty) {
      return state.hasSearched
          ? EmptyStateWidget(
              icon: Icons.search_off_rounded,
              title: context.l10n.browseNoResultsFound,
              subtitle:
                  '${context.l10n.browseNoYtmMatchesFor} "${state.query.trim()}".',
            )
          : _buildHistory(context, p);
    }

    final status = cubit.statusMessage;
    final songs = [for (final track in state.results) track.toSongData()];
    return Column(
      children: [
        if (status != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.accent.withValues(alpha: 0.35)),
            ),
            child: Text(
              status,
              style: TextStyle(fontSize: 11.5, color: p.textSecondary),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              cubit.retry();
              await Future.delayed(const Duration(milliseconds: 300));
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 160, top: 4),
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return SongTile(
                  song: song,
                  subtitleOverride: state.results[index].artist,
                  onTap: () => playerCubit.playSong(song, queue: songs),
                  trailing: YtmDownloadButton(song: song),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
