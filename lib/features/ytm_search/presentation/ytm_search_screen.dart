import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../player/cubit/player_cubit.dart';
import '../cubit/ytm_download_cubit.dart';
import '../cubit/ytm_search_cubit.dart';
import '../cubit/ytm_search_state.dart';
import 'widgets/ytm_download_button.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
  List<String> _history = const [];
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  Future<void> _refreshHistory() async {
    try {
      final items = await context.read<YtmSearchCubit>().getSearchHistory();
      if (mounted) {
        setState(() {
          _history = items;
          _historyLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _history = const [];
          _historyLoaded = true;
        });
      }
    }
  }

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
            child: BlocListener<YtmSearchCubit, YtmSearchState>(
              listenWhen: (prev, curr) =>
                  prev.results != curr.results && curr.results.isNotEmpty,
              listener: (_, __) => _refreshHistory(),
              child: BlocBuilder<YtmSearchCubit, YtmSearchState>(
              builder: (context, state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
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
                                    tooltip: context.l10n.clear,
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
    if (!_historyLoaded) {
      return const SizedBox.shrink();
    }
    if (_history.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.travel_explore_rounded,
        title: context.l10n.searchYtm,
        subtitle: context.l10n.browseYtmSearchScreenDesc,
      );
    }
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.xxs, AppSpacing.md, 160),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.history,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                await cubit.clearHistory();
                if (mounted) _refreshHistory();
              },
              child: Text(context.l10n.browseClearHistory),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final h in _history)
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
        const SizedBox(height: AppSpacing.md),
        Text(
          context.l10n.browseYtmSearchScreenDesc,
          style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.label),
        ),
      ],
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
        return const SkeletonList(
            padding: EdgeInsets.only(top: AppSpacing.xs));
      }

    if (state.errorMessage != null) {
      return EmptyStateWidget(
        icon: Icons.cloud_off_rounded,
        title: context.l10n.browseSearchFailed,
        subtitle: state.errorMessage!,
        primaryActionLabel: context.l10n.tryAgain,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: cubit.retryAfterCooldown,
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

    final songs = [for (final track in state.results) track.toSongData()];
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: cubit.botCooldown,
          builder: (context, coolingDown, _) {
            final status = cubit.statusMessageFor(coolingDown);
            if (status == null) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              margin: const EdgeInsetsDirectional.fromSTEB(AppSpacing.sm, AppSpacing.xxs, AppSpacing.sm, AppSpacing.xxs),
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.r10),
                border: Border.all(color: p.accent.withValues(alpha: 0.35)),
              ),
              child: Text(
                status,
                style: TextStyle(fontSize: AppFontSize.label, color: p.textSecondary),
              ),
            );
          },
        ),
        Expanded(
          child: RefreshIndicator(
            color: p.accent,
            backgroundColor: p.surfaceContainer,
            onRefresh: () async {
              cubit.retry();
              await Future.delayed(const Duration(milliseconds: 300));
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.scrollBottom, top: AppSpacing.xxs),
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
