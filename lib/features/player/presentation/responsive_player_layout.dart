// lib/features/player/presentation/responsive_player_layout.dart
import 'dart:ui' show DisplayFeature, DisplayFeatureType;
import 'package:flutter/material.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/adaptive.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'widgets/lyrics_view.dart';
import 'widgets/now_playing_queue_view.dart';
import 'widgets/player_controls.dart';
import 'widgets/waveform_seek_bar.dart';

/// Responsive layout coordinator for the Now Playing screen.
///
/// Automatically adapts between:
/// 1. Tabletop Mode (foldables half-folded along horizontal hinge)
/// 2. Tablet Split-View (screens with width > 840dp)
/// 3. Standard Single-Pane Layout (phones and compact screens)
class ResponsivePlayerLayout extends StatefulWidget {
  final PlayerState state;
  final PlayerCubit cubit;
  final Widget themeWidget;
  final Color activeColor;
  final Color bgColor;

  const ResponsivePlayerLayout({
    super.key,
    required this.state,
    required this.cubit,
    required this.themeWidget,
    required this.activeColor,
    required this.bgColor,
  });

  @override
  State<ResponsivePlayerLayout> createState() => _ResponsivePlayerLayoutState();
}

class _ResponsivePlayerLayoutState extends State<ResponsivePlayerLayout>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DisplayFeature? _findHorizontalHinge(BuildContext context) {
    for (final feature in MediaQuery.displayFeaturesOf(context)) {
      if ((feature.type == DisplayFeatureType.hinge ||
              feature.type == DisplayFeatureType.fold) &&
          feature.bounds.width > feature.bounds.height) {
        return feature;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width;
    final hinge = _findHorizontalHinge(context);

    // 1. Tabletop Mode for Foldables (horizontal fold detected)
    if (hinge != null) {
      final topHeight = hinge.bounds.top;
      final bottomHeight = mediaQuery.size.height - hinge.bounds.bottom;

      return Column(
        children: [
          // Upper half: Album Art + Lyrics Focus
          SizedBox(
            height: topHeight,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.r20),
                child: widget.themeWidget,
              ),
            ),
          ),
          // Hinge spacer
          SizedBox(height: hinge.bounds.height),
          // Lower half: Waveform, Transport Controls, and Queue preview
          SizedBox(
            height: bottomHeight,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  WaveformSeekBar(
                    position: widget.state.position,
                    duration: widget.state.duration,
                    samples: const [],
                    activeColor: widget.activeColor,
                    onSeek: (pos) => widget.cubit.seek(pos),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PlayerControls(
                    isPlaying: widget.state.isPlaying,
                    isShuffle: widget.state.isShuffle,
                    repeatMode: widget.state.repeatMode,
                    primaryColor: widget.activeColor,
                    onPlayPause: () => widget.cubit.togglePlayPause(),
                    onNext: () => widget.cubit.next(),
                    onPrevious: () => widget.cubit.previous(),
                    onToggleShuffle: () => widget.cubit.toggleShuffle(),
                    onToggleRepeat: () => widget.cubit.toggleRepeat(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    widget.state.currentSong?.title ?? '',
                    style: TextStyle(
                      color: widget.activeColor,
                      fontSize: AppFontSize.body,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 2. Tablet / Desktop Split-View
    // Must be an actual tablet or desktop (height >= 550) to prevent landscape phones
    // (which have width 840-932 but height ~360-430) from triggering the 2-pane tablet split.
    // Landscape phones render the immersive full-screen player theme directly.
    final isTabletLandscape =
        (width >= 840 && mediaQuery.size.height >= 550) ||
        (Adaptive.isTablet(context) && width >= 720 && mediaQuery.size.height >= 550);
    if (isTabletLandscape) {
      return Row(
        children: [
          // Left Pane: Persistent Full-Fidelity Player Theme
          Expanded(
            flex: 5,
            child: Container(
              margin: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.r24),
              ),
              clipBehavior: Clip.antiAlias,
              child: widget.themeWidget,
            ),
          ),
          // Divider
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: widget.activeColor.withValues(alpha: 0.15),
          ),
          // Right Pane: Tabbed View (Queue / Lyrics / Quick DSP)
          Expanded(
            flex: 4,
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  indicatorColor: widget.activeColor,
                  labelColor: widget.activeColor,
                  unselectedLabelColor: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withValues(alpha: 0.6),
                  tabs: const [
                    Tab(icon: Icon(Icons.queue_music_rounded), text: 'Queue'),
                    Tab(icon: Icon(Icons.lyrics_rounded), text: 'Lyrics'),
                    Tab(icon: Icon(Icons.tune_rounded), text: 'DSP'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Queue View
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: NowPlayingQueueView(),
                      ),
                      // Lyrics View
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: LyricsView(
                          currentPosition: widget.state.position,
                          lyrics: widget.state.lyrics,
                          activeColor: widget.activeColor,
                        ),
                      ),
                      // Quick DSP Quick-Controls
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: _QuickDspControls(
                          cubit: widget.cubit,
                          state: widget.state,
                          activeColor: widget.activeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 3. Single-Pane Layout (Phone / Standard)
    return widget.themeWidget;
  }
}

class _QuickDspControls extends StatelessWidget {
  final PlayerCubit cubit;
  final PlayerState state;
  final Color activeColor;

  const _QuickDspControls({
    required this.cubit,
    required this.state,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(
          'Quick DSP Controls',
          style: TextStyle(
            fontSize: AppFontSize.title,
            fontWeight: FontWeight.w800,
            color: activeColor,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SwitchListTile(
          title: const Text('Equalizer Engine'),
          subtitle: const Text('Direct biquad parametric filtering'),
          value: state.isEqEnabled,
          activeTrackColor: activeColor,
          onChanged: (v) => cubit.setEqualizerEnabled(v),
        ),
        SwitchListTile(
          title: const Text('True Peak Limiter'),
          subtitle: const Text('Zero inter-sample clipping'),
          value: state.isLimiterEnabled,
          activeTrackColor: activeColor,
          onChanged: (v) => cubit.setLookaheadLimiter(v),
        ),
        SwitchListTile(
          title: const Text('ViPER-DDC Headphone Correction'),
          subtitle: Text(
            state.viperDdcProfileName.isNotEmpty
                ? state.viperDdcProfileName
                : 'No profile loaded',
          ),
          value: state.isViperDdcEnabled,
          activeTrackColor: activeColor,
          onChanged: (v) => cubit.setViperDdcEnabled(v),
        ),
      ],
    );
  }
}
