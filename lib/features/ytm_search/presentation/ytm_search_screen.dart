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

  @override
  void dispose() {
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
          : EmptyStateWidget(
              icon: Icons.travel_explore_rounded,
              title: context.l10n.searchYtm,
              subtitle: context.l10n.browseYtmSearchScreenDesc,
            );
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
