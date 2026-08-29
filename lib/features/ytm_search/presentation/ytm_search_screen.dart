import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/widgets/empty_state_widget.dart';
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
        // YtmSearchCubit is factory-registered: fresh instance owned + closed by this screen.
        BlocProvider(create: (_) => getIt<YtmSearchCubit>()),
        // YtmDownloadCubit is an app-lifetime @singleton provided at root (main.dart).
        // BlocProvider.value does NOT take ownership, so leaving this screen can never
        // close the shared singleton (use-after-close would kill download UI updates).
        BlocProvider<YtmDownloadCubit>.value(value: getIt<YtmDownloadCubit>()),
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

    return Scaffold(
      appBar: AppBar(title: const Text('YouTube Music')),
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
                          hintText: 'Songs on YouTube Music…',
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
        title: 'Search Failed',
        subtitle: state.errorMessage!,
        primaryActionLabel: 'Try Again',
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: cubit.retry,
      );
    }

    if (state.results.isEmpty) {
      return state.hasSearched
          ? EmptyStateWidget(
              icon: Icons.search_off_rounded,
              title: 'No Results Found',
              subtitle: 'No YouTube Music matches for "${state.query.trim()}".',
            )
          : const EmptyStateWidget(
              icon: Icons.travel_explore_rounded,
              title: 'Search YouTube Music',
              subtitle:
                  'Stream and download songs from YouTube Music, ad-free.',
            );
    }

    final songs = [for (final track in state.results) track.toSongData()];
    return RefreshIndicator(
      onRefresh: () async {
        unawaited(cubit.retry());
        await Future<void>.delayed(const Duration(milliseconds: 300));
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
    );
  }
}
