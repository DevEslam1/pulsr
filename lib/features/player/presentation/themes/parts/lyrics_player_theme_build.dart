part of '../lyrics_player_theme.dart';

extension _LyricsPlayerThemeBuild on LyricsPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final p = context.palette;
    final activeColor = props.activeColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = context.select<SettingsCubit, AppThemeMode>(
      (c) => c.state.themeMode,
    );
    final customGlow = resolveCustomGlow(context);
    final artRadius = resolveCustomRadius(context, AppRadii.r10);
    final pillRadius = resolveCustomRadius(context, AppRadii.r28);

    return PlayerSurfaceShell(
      props: props,
      handlesLyricsInline: true,
      background: _KaraokeStageBackdrop(
        activeColor: activeColor,
        bgColor: props.bgColor,
        isDark: isDark,
        isAmoled: themeMode == AppThemeMode.amoled ||
            (p.isDark && p.bg == Colors.black),
        customGlow: customGlow,
      ),
      builder: (context, metrics, isInSplitView, isPreview) {
        final isCompact = metrics.isVeryShortHeight || metrics.isLandscape;
        final horizontalPad = metrics.isTablet ? AppSpacing.lg : AppSpacing.md;

        final Widget body = Column(
          children: [
            // 1. Compact Top Bar (40x40 art thumbnail + metadata + quick actions)
            _KaraokeCompactHeader(
              props: props,
              artRadius: artRadius,
              isInSplitView: isInSplitView,
              isPreview: isPreview,
              isCompact: isCompact,
              horizontalPad: horizontalPad,
            ),

            // 2. Lyrics-First Stage (~70% of viewport)
            Expanded(
              child: _KaraokeLyricsStage(
                props: props,
                activeColor: activeColor,
                metrics: metrics,
                isPreview: isPreview,
                isInSplitView: isInSplitView,
                customGlow: customGlow,
              ),
            ),

            // 3. Ultra-Slim Floating Translucent Transport + Progress Pill
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                horizontalPad,
                isCompact ? AppSpacing.xxs : AppSpacing.xs,
                horizontalPad,
                isCompact ? AppSpacing.xs : AppSpacing.sm,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: _KaraokeFloatingPill(
                    props: props,
                    activeColor: activeColor,
                    pillRadius: pillRadius,
                    isCompact: isCompact,
                    isPreview: isPreview,
                    customGlow: customGlow,
                    palette: p,
                  ),
                ),
              ),
            ),
          ],
        );

        if (isInSplitView || isPreview) {
          return body;
        }
        return SafeArea(
          top: true,
          bottom: true,
          child: body,
        );
      },
    );
  }
}

/// Rich ambient stage gradient tinted from album artwork colors with subtle
/// upper/center spotlight glow (avoiding a harsh pure-black void).
class _KaraokeStageBackdrop extends StatelessWidget {
  final Color activeColor;
  final Color bgColor;
  final bool isDark;
  final bool isAmoled;
  final bool customGlow;

  const _KaraokeStageBackdrop({
    required this.activeColor,
    required this.bgColor,
    required this.isDark,
    required this.isAmoled,
    required this.customGlow,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isHighContrast =
        p.isHighContrast || MediaQuery.highContrastOf(context);
    if (isHighContrast) {
      return ColoredBox(color: p.bg);
    }
    final surface = context.playerSurfacePalette;
    final glowBoost = customGlow ? 1.32 : 1.0;

    final Color topTint;
    final Color midTint;
    final Color bottomTint;

    if (isDark) {
      final base = isAmoled
          ? Color.alphaBlend(
              activeColor.withValues(alpha: 0.14),
              p.surface,
            )
          : Color.alphaBlend(
              activeColor.withValues(alpha: 0.22),
              bgColor,
            );
      topTint = Color.alphaBlend(
        activeColor.withValues(alpha: isAmoled ? 0.16 : 0.26),
        base,
      );
      midTint = Color.alphaBlend(
        surface.shadowAt(isAmoled ? 0.56 : 0.34),
        base,
      );
      bottomTint = Color.alphaBlend(
        surface.shadowAt(isAmoled ? 0.72 : 0.54),
        bgColor,
      );
    } else {
      topTint = Color.alphaBlend(
        activeColor.withValues(alpha: 0.16),
        bgColor,
      );
      midTint = Color.alphaBlend(
        activeColor.withValues(alpha: 0.08),
        p.bg,
      );
      bottomTint = Color.alphaBlend(
        activeColor.withValues(alpha: 0.12),
        p.surfaceContainer,
      );
    }

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.52, 1.0],
                colors: [topTint, midTint, bottomTint],
              ),
            ),
          ),
          // Soft stage spotlight centered behind the active lyric line
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, -0.14),
                radius: 0.95,
                colors: [
                  activeColor.withValues(
                    alpha: ((isDark ? 0.26 : 0.16) * glowBoost).clamp(0.0, 0.45),
                  ),
                  activeColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // Secondary lower ambient stage wash
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.65, 0.78),
                radius: 0.9,
                colors: [
                  activeColor.withValues(
                    alpha: ((isDark ? 0.15 : 0.10) * glowBoost).clamp(0.0, 0.30),
                  ),
                  activeColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact Lyrics-First header: dismiss chevron + 40x40 album art thumbnail +
/// title & artist + favorite heart + Queue toggle + [PlayerToolsTriggerButton].
class _KaraokeCompactHeader extends StatelessWidget {
  final PlayerThemeProps props;
  final double artRadius;
  final bool isInSplitView;
  final bool isPreview;
  final bool isCompact;
  final double horizontalPad;

  const _KaraokeCompactHeader({
    required this.props,
    required this.artRadius,
    required this.isInSplitView,
    required this.isPreview,
    required this.isCompact,
    required this.horizontalPad,
  });

  void _dismiss(BuildContext context) {
    try {
      final router = GoRouter.of(context);
      if (router.canPop()) {
        router.pop();
        return;
      }
      router.go('/');
    } catch (_) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final state = props.state;
    final song = state.currentSong;
    final isFav = song?.isFavorite == true;
    final activeColor = props.activeColor;
    final clampedThumbRadius = artRadius.clamp(4.0, 20.0);
    final double thumbSize = isCompact ? 36.0 : 40.0;

    final Color buttonSurface = p.isDark
        ? AppColors.specularAt(0.08)
        : p.surface.withValues(alpha: 0.72);
    final Color buttonBorder = p.hairline;

    final Widget artworkThumb = Hero(
      tag: props.heroTag,
      child: Container(
        width: thumbSize,
        height: thumbSize,
        decoration: BoxDecoration(
          borderRadius: AppRadii.circular(clampedThumbRadius),
          border: Border.all(
            color: state.isPlaying
                ? activeColor.withValues(alpha: 0.50)
                : buttonBorder,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: activeColor.withValues(
                alpha: state.isPlaying ? 0.28 : 0.12,
              ),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadii.circular(clampedThumbRadius),
          child: PlayerArtworkSemantics(
            song: song,
            child: song != null
                ? CachedArtwork(
                    id: song.id,
                    albumId: song.albumId,
                    remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                    type: ArtworkType.AUDIO,
                    size: thumbSize,
                    borderRadius: clampedThumbRadius,
                    highQuality: true,
                  )
                : ColoredBox(
                    color: p.surfaceContainerHigh,
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 18,
                      color: p.textSecondary,
                    ),
                  ),
          ),
        ),
      ),
    );

    final String titleText = song?.title ?? l10n.noTrackSelected;
    final String artistText = song?.artist ?? l10n.unknownArtist;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        isInSplitView || isPreview ? horizontalPad : AppSpacing.xs,
        isCompact ? AppSpacing.xxs : AppSpacing.xs,
        isPreview ? horizontalPad : AppSpacing.xs,
        isCompact ? AppSpacing.xxs : AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!isInSplitView && !isPreview)
            PlayerIconActionButton(
              icon: Icons.keyboard_arrow_down_rounded,
              tooltip: l10n.close,
              iconColor: p.textPrimary,
              iconSize: 26,
              onTap: () => _dismiss(context),
            ),
          if (!isInSplitView && !isPreview)
            const SizedBox(width: AppSpacing.xxs),
          artworkThumb,
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isPreview)
                  Text(
                    titleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.body,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                      letterSpacing: AppTracking.title,
                    ),
                  )
                else
                  MarqueeText(
                    text: titleText,
                    style: TextStyle(
                      fontSize:
                          isCompact ? AppFontSize.body : AppFontSize.callout,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                      letterSpacing: AppTracking.title,
                    ),
                  ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  artistText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (isPreview)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.20),
                borderRadius: AppRadii.full,
                border: Border.all(
                  color: activeColor.withValues(alpha: 0.42),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_rounded, size: 12, color: activeColor),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    l10n.lyrics,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w800,
                      color: activeColor,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Material(
              color: AppColors.fadeStopTransparent,
              child: PlayerAnimatedFavoriteButton(
                isFavorite: isFav,
                favoriteColor: p.favorite,
                inactiveColor: p.textSecondary,
                iconSize: 21,
                semanticLabel: isFav ? l10n.unlike : l10n.like,
                onTap: () {
                  if (song != null) {
                    props.cubit.toggleFavorite(song.id);
                  }
                },
              ),
            ),
            if (!isInSplitView)
              PlayerIconActionButton(
                icon: Icons.queue_music_rounded,
                tooltip: l10n.queue,
                isActive: state.isQueueVisible,
                activeColor: activeColor,
                iconColor: p.textPrimary,
                iconSize: 22,
                onTap: props.cubit.toggleQueueVisibility,
              ),
            PlayerToolsTriggerButton(
              props: props,
              iconColor: p.textPrimary,
              backgroundColor: buttonSurface,
              borderColor: buttonBorder,
              iconSize: 20,
            ),
          ],
        ],
      ),
    );
  }
}

/// Primary ~70%-viewport Karaoke Lyrics Stage.
class _KaraokeLyricsStage extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final PlayerThemeMetrics metrics;
  final bool isPreview;
  final bool isInSplitView;
  final bool customGlow;

  const _KaraokeLyricsStage({
    required this.props,
    required this.activeColor,
    required this.metrics,
    required this.isPreview,
    required this.isInSplitView,
    required this.customGlow,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;

    if (isPreview) {
      return _KaraokePreviewStage(
        lines: state.lyrics,
        songTitle: state.currentSong?.title,
        activeColor: activeColor,
        customGlow: customGlow,
      );
    }

    if (state.isLoadingLyrics) {
      return _KaraokeLoadingStage(activeColor: activeColor);
    }

    if (state.lyrics.isEmpty) {
      return PlayerGestureScope(
        child: _KaraokeEmptyStage(
          activeColor: activeColor,
          isCompact: metrics.isVeryShortHeight || metrics.isLandscape,
          onRefresh: () {
            PulsrHaptics.selectionClick();
            props.cubit.refreshLyrics();
          },
        ),
      );
    }

    final bool hasTimedLyrics = state.lyrics.any(
      (line) => line.timestamp > Duration.zero || line.words.isNotEmpty,
    );
    final bool hasWordSync =
        state.lyrics.any((line) => line.words.isNotEmpty);

    final Widget stageContent;
    if (hasWordSync) {
      stageContent = ShaderMask(
        shaderCallback: _stageFadeShader,
        blendMode: BlendMode.dstIn,
        child: BlocSelector<PlayerCubit, PlayerState, Duration>(
          selector: (s) => s.position,
          builder: (context, position) => AdvancedLyricsView(
            lyrics: state.lyrics,
            currentPosition: position,
            activeColor: activeColor,
            onLineTapped: props.cubit.seek,
          ),
        ),
      );
    } else if (hasTimedLyrics) {
      stageContent = ShaderMask(
        shaderCallback: _stageFadeShader,
        blendMode: BlendMode.dstIn,
        child: _KaraokeSyncedLrcList(
          lines: state.lyrics,
          activeColor: activeColor,
          isCompact: metrics.isVeryShortHeight || metrics.isLandscape,
          isTablet: metrics.isTablet,
          customGlow: customGlow,
          onSeek: props.cubit.seek,
        ),
      );
    } else {
      stageContent = _KaraokeUnsyncedList(
        lines: state.lyrics,
        activeColor: activeColor,
        isCompact: metrics.isVeryShortHeight || metrics.isLandscape,
        onRefresh: () {
          PulsrHaptics.selectionClick();
          props.cubit.refreshLyrics();
        },
      );
    }

    return PlayerGestureScope(
      behavior: HitTestBehavior.translucent,
      child: stageContent,
    );
  }

  static Shader _stageFadeShader(Rect bounds) {
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppColors.fadeStopTransparent,
        AppColors.fadeStopOpaque,
        AppColors.fadeStopOpaque,
        AppColors.fadeStopTransparent,
      ],
      stops: [0.0, 0.12, 0.86, 1.0],
    ).createShader(bounds);
  }
}

/// Binary search for the active LRC line at [position], or -1 during intro.
int _activeLyricLineIndex(List<LyricsLine> lines, Duration position) {
  if (lines.isEmpty) return -1;
  final int positionMs = position.inMilliseconds;
  int low = 0;
  int high = lines.length - 1;
  int active = -1;
  while (low <= high) {
    final int mid = (low + high) >> 1;
    if (lines[mid].timestamp.inMilliseconds <= positionMs) {
      active = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return active;
}

/// Synced LRC scrolling list driven exclusively by `BlocSelector<PlayerCubit, PlayerState, int>`
/// (rebuilds ONLY when the singing line changes — zero full-theme rebuilds).
class _KaraokeSyncedLrcList extends StatefulWidget {
  final List<LyricsLine> lines;
  final Color activeColor;
  final bool isCompact;
  final bool isTablet;
  final bool customGlow;
  final ValueChanged<Duration> onSeek;

  const _KaraokeSyncedLrcList({
    required this.lines,
    required this.activeColor,
    required this.isCompact,
    required this.isTablet,
    required this.customGlow,
    required this.onSeek,
  });

  @override
  State<_KaraokeSyncedLrcList> createState() => _KaraokeSyncedLrcListState();
}

class _KaraokeSyncedLrcListState extends State<_KaraokeSyncedLrcList> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  late List<LyricsLine> _sorted;
  int _lastActiveIndex = -1;
  bool _userIsScrolling = false;
  DateTime _lastUserScrollTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _sorted = _orderedLines(widget.lines);
  }

  @override
  void didUpdateWidget(covariant _KaraokeSyncedLrcList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lines, widget.lines)) {
      _sorted = _orderedLines(widget.lines);
      if (_lineKeys.length > _sorted.length) {
        _lineKeys.removeWhere((idx, _) => idx >= _sorted.length);
      }
      _lastActiveIndex = -1;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static List<LyricsLine> _orderedLines(List<LyricsLine> lines) {
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].timestamp < lines[i - 1].timestamp) {
        return List<LyricsLine>.of(lines)
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
    }
    return lines;
  }

  GlobalKey _keyFor(int index) =>
      _lineKeys.putIfAbsent(index, () => GlobalKey());

  void _scrollToIndex(int index) {
    if (index < 0 || !_scrollController.hasClients) return;
    final now = DateTime.now();
    if (_userIsScrolling && now.difference(_lastUserScrollTime).inSeconds < 3) {
      return;
    }
    _userIsScrolling = false;

    final ctx = _lineKeys[index]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.40,
        duration: context.motionMs(320),
        curve: context.motionCurve(Curves.easeOutCubic),
      );
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final deferredCtx = _lineKeys[index]?.currentContext;
      if (deferredCtx != null) {
        Scrollable.ensureVisible(
          deferredCtx,
          alignment: 0.40,
          duration: context.motionMs(320),
          curve: context.motionCurve(Curves.easeOutCubic),
        );
      } else {
        final target = (index * 64.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        if (!PulsrMotion.shouldAnimate(context)) {
          _scrollController.jumpTo(target);
        } else {
          _scrollController.animateTo(
            target,
            duration: context.motionMs(320),
            curve: context.motionCurve(Curves.easeOutCubic),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<PlayerCubit, PlayerState, int>(
      selector: (s) => _activeLyricLineIndex(_sorted, s.position),
      builder: (context, activeIndex) {
        if (activeIndex != _lastActiveIndex && activeIndex >= 0) {
          _lastActiveIndex = activeIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToIndex(activeIndex);
          });
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final verticalEdgePad = math.max(
              AppSpacing.lg,
              constraints.maxHeight * 0.28,
            );
            final horizontalPad =
                widget.isTablet ? AppSpacing.xl : AppSpacing.lg;

            return NotificationListener<UserScrollNotification>(
              onNotification: (_) {
                _userIsScrolling = true;
                _lastUserScrollTime = DateTime.now();
                return false;
              },
              child: ListView.builder(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  vertical: verticalEdgePad,
                  horizontal: horizontalPad,
                ),
                itemCount: _sorted.length,
                itemBuilder: (context, index) {
                  final line = _sorted[index];
                  final isActive = index == activeIndex;
                  final distance =
                      activeIndex >= 0 ? (index - activeIndex).abs() : index;

                  return KeyedSubtree(
                    key: _keyFor(index),
                    child: _KaraokeSyncedLineTile(
                      line: line,
                      isActive: isActive,
                      distance: distance,
                      activeColor: widget.activeColor,
                      isCompact: widget.isCompact,
                      isTablet: widget.isTablet,
                      customGlow: widget.customGlow,
                      onTap: () {
                        PulsrHaptics.selectionClick();
                        widget.onSeek(line.timestamp);
                      },
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _KaraokeSyncedLineTile extends StatelessWidget {
  final LyricsLine line;
  final bool isActive;
  final int distance;
  final Color activeColor;
  final bool isCompact;
  final bool isTablet;
  final bool customGlow;
  final VoidCallback onTap;

  const _KaraokeSyncedLineTile({
    required this.line,
    required this.isActive,
    required this.distance,
    required this.activeColor,
    required this.isCompact,
    required this.isTablet,
    required this.customGlow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = line.text.trim();
    if (text.isEmpty) {
      return const SizedBox(height: AppSpacing.md);
    }

    final alignEnd = line.alignment == LyricAlignment.end;
    final isBackground = line.isBackgroundLine;
    final subText = line.translation ?? line.romanization;

    final double lineOpacity;
    final double blurSigma;
    if (isActive) {
      lineOpacity = 1.0;
      blurSigma = 0.0;
    } else if (distance == 1) {
      lineOpacity = 0.64;
      blurSigma = 0.0;
    } else if (distance == 2) {
      lineOpacity = 0.42;
      blurSigma = 0.6;
    } else {
      lineOpacity = (0.30 - (distance - 3) * 0.03).clamp(0.18, 0.30);
      blurSigma = 1.2;
    }

    final double activeSize = isBackground
        ? AppFontSize.title
        : (isCompact
            ? AppFontSize.titleLarge
            : (isTablet ? AppFontSize.display : AppFontSize.headline));
    final double inactiveSize = isBackground
        ? AppFontSize.bodyLarge
        : (isCompact
            ? AppFontSize.subtitle
            : (isTablet ? AppFontSize.titleMedium : AppFontSize.title));

    final double glowAlpha = customGlow ? 0.65 : 0.48;

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          text,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: isActive ? activeSize : inactiveSize,
            fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
            fontStyle: isBackground ? FontStyle.italic : FontStyle.normal,
            height: 1.32,
            letterSpacing: isActive ? AppTracking.heading : AppTracking.title,
            color: isActive ? activeColor : p.textSecondary,
            shadows: (isActive && !p.isCalmDensity)
                ? [
                    Shadow(
                      color: activeColor.withValues(alpha: glowAlpha),
                      blurRadius: customGlow ? 24 : 18,
                    ),
                    Shadow(
                      color: activeColor.withValues(alpha: glowAlpha * 0.55),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        ),
        if (subText != null && subText.trim().isNotEmpty && subText != text)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              subText.trim(),
              textAlign: alignEnd ? TextAlign.end : TextAlign.start,
              style: TextStyle(
                fontSize: AppFontSize.body,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
                color: isActive
                    ? activeColor.withValues(alpha: 0.90)
                    : p.textTertiary,
              ),
            ),
          ),
      ],
    );

    if (blurSigma > 0.0 && AppBlur.canBlur(context)) {
      final clamped = AppBlur.clampSigma(blurSigma);
      content = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: clamped, sigmaY: clamped),
        child: content,
      );
    }

    return Semantics(
      button: true,
      selected: isActive,
      label: text,
      excludeSemantics: true,
      child: Material(
        color: AppColors.fadeStopTransparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.r16All,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: AnimatedOpacity(
              duration: context.motionMs(260),
              curve: context.motionCurve(Curves.easeOutCubic),
              opacity: lineOpacity,
              child: AnimatedContainer(
                duration: context.motionMs(260),
                curve: context.motionCurve(Curves.easeOutCubic),
                padding: EdgeInsets.symmetric(
                  vertical: isCompact ? AppSpacing.s6 : AppSpacing.s10,
                  horizontal: AppSpacing.sm,
                ),
                decoration: isActive
                    ? BoxDecoration(
                        borderRadius: AppRadii.r16All,
                        color: activeColor.withValues(
                          alpha: p.isDark ? 0.10 : 0.08,
                        ),
                      )
                    : null,
                alignment:
                    alignEnd ? Alignment.centerRight : Alignment.centerLeft,
                child: AnimatedScale(
                  scale: isActive ? 1.03 : 0.97,
                  duration: context.motionMs(260),
                  curve: context.motionCurve(Curves.easeOutCubic),
                  alignment:
                      alignEnd ? Alignment.centerRight : Alignment.centerLeft,
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clean scrollable unsynced plain-text lyrics stage with subtle refresh chip.
class _KaraokeUnsyncedList extends StatelessWidget {
  final List<LyricsLine> lines;
  final Color activeColor;
  final bool isCompact;
  final VoidCallback onRefresh;

  const _KaraokeUnsyncedList({
    required this.lines,
    required this.activeColor,
    required this.isCompact,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s10,
                    vertical: AppSpacing.s4,
                  ),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.14),
                    borderRadius: AppRadii.full,
                    border: Border.all(
                      color: activeColor.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Text(
                    l10n.dspEmbeddedUnsynced,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                      color: activeColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              PlayerIconActionButton(
                icon: Icons.refresh_rounded,
                tooltip: l10n.searchLyrics,
                iconColor: activeColor,
                iconSize: 18,
                onTap: onRefresh,
              ),
            ],
          ),
        ),
        Expanded(
          child: ShaderMask(
            shaderCallback: _KaraokeLyricsStage._stageFadeShader,
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: isCompact ? AppSpacing.md : AppSpacing.xl,
              ),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final text = lines[index].text.trim();
                if (text.isEmpty) {
                  return const SizedBox(height: AppSpacing.sm);
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
                  child: Text(
                    text,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize:
                          isCompact ? AppFontSize.bodyLarge : AppFontSize.title,
                      fontWeight: FontWeight.w600,
                      height: 1.48,
                      color: p.textPrimary.withValues(alpha: 0.90),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Clean loading skeleton stage (no `CircularProgressIndicator` added).
class _KaraokeLoadingStage extends StatelessWidget {
  final Color activeColor;

  const _KaraokeLoadingStage({required this.activeColor});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LyricSkeletonBar(widthFactor: 0.62, opacity: 0.22, color: p.textSecondary),
            const SizedBox(height: AppSpacing.md),
            _LyricSkeletonBar(
              widthFactor: 0.90,
              height: 22,
              opacity: 0.55,
              color: activeColor,
            ),
            const SizedBox(height: AppSpacing.md),
            _LyricSkeletonBar(widthFactor: 0.74, opacity: 0.24, color: p.textSecondary),
            const SizedBox(height: AppSpacing.sm),
            _LyricSkeletonBar(widthFactor: 0.48, opacity: 0.16, color: p.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _LyricSkeletonBar extends StatelessWidget {
  final double widthFactor;
  final double height;
  final double opacity;
  final Color color;

  const _LyricSkeletonBar({
    required this.widthFactor,
    this.height = 16,
    required this.opacity,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: opacity),
          borderRadius: AppRadii.full,
        ),
      ),
    );
  }
}

/// Clean empty / instrumental lyrics stage with Search Lyrics action.
class _KaraokeEmptyStage extends StatelessWidget {
  final Color activeColor;
  final bool isCompact;
  final VoidCallback onRefresh;

  const _KaraokeEmptyStage({
    required this.activeColor,
    required this.isCompact,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: isCompact ? AppSpacing.xs : AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isCompact ? 48 : 64,
              height: isCompact ? 48 : 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: activeColor.withValues(alpha: 0.16),
                border: Border.all(
                  color: activeColor.withValues(alpha: 0.36),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.22),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Icon(
                Icons.mic_none_rounded,
                size: isCompact ? 24 : 30,
                color: activeColor,
              ),
            ),
            SizedBox(height: isCompact ? AppSpacing.xs : AppSpacing.md),
            Text(
              l10n.noLyricsFound,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: isCompact ? AppFontSize.callout : AppFontSize.title,
                fontWeight: FontWeight.w800,
                color: p.textPrimary,
              ),
            ),
            if (!isCompact) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.placeLrcHint,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFontSize.bodySmall,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: p.textSecondary,
                ),
              ),
            ],
            SizedBox(height: isCompact ? AppSpacing.sm : AppSpacing.md),
            Semantics(
              button: true,
              label: l10n.searchLyrics,
              excludeSemantics: true,
              child: Material(
                color: activeColor.withValues(alpha: 0.18),
                shape: StadiumBorder(
                  side: BorderSide(
                    color: activeColor.withValues(alpha: 0.46),
                    width: 1.0,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onRefresh,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 18,
                            color: activeColor,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              l10n.searchLyrics,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.bodySmall,
                                fontWeight: FontWeight.w800,
                                color: activeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stylized multi-line Karaoke Stage preview shown inside Theme Picker & Theme
/// Studio (`PlayerThemePreviewScope`), so the mini-preview is unmistakably a
/// Lyrics-First Stage with a magnified glowing active line and zero overflow.
class _KaraokePreviewStage extends StatelessWidget {
  final List<LyricsLine> lines;
  final String? songTitle;
  final Color activeColor;
  final bool customGlow;

  const _KaraokePreviewStage({
    required this.lines,
    required this.songTitle,
    required this.activeColor,
    required this.customGlow,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sample = lines.isNotEmpty
        ? lines.take(5).map((l) => l.text.trim()).where((t) => t.isNotEmpty).toList()
        : <String>[
            'Echoes drift across the twilight air',
            'Every chord illuminating the dark',
            (songTitle != null && songTitle!.trim().isNotEmpty)
                ? songTitle!.trim()
                : 'Singing in the glow of every line',
            'Waves of rhythm carry us away',
            'Until the quiet fade of morning light',
          ];

    final int highlightIdx = sample.length >= 3 ? 2 : 0;

    return ShaderMask(
      shaderCallback: _KaraokeLyricsStage._stageFadeShader,
      blendMode: BlendMode.dstIn,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: ClipRect(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < sample.length; i++)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
                    child: Container(
                      padding: i == highlightIdx
                          ? const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            )
                          : const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                            ),
                      decoration: i == highlightIdx
                          ? BoxDecoration(
                              color: activeColor.withValues(
                                alpha: p.isDark ? 0.14 : 0.10,
                              ),
                              borderRadius: AppRadii.r14All,
                            )
                          : null,
                      child: Text(
                        sample[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: i == highlightIdx
                              ? AppFontSize.headline
                              : AppFontSize.bodyLarge,
                          fontWeight: i == highlightIdx
                              ? FontWeight.w900
                              : FontWeight.w700,
                          color: i == highlightIdx
                              ? (p.isDark
                                  ? Color.lerp(p.textPrimary, activeColor, 0.22)
                                  : activeColor)
                              : p.textSecondary.withValues(
                                  alpha: (i - highlightIdx).abs() == 1
                                      ? 0.58
                                      : 0.30,
                                ),
                          shadows: (i == highlightIdx && !p.isCalmDensity)
                              ? [
                                  Shadow(
                                    color: activeColor.withValues(
                                      alpha: customGlow ? 0.72 : 0.52,
                                    ),
                                    blurRadius: 18,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ultra-slim floating translucent pill housing interactive progress bar
/// (`BlocSelector` for position) and compact transport controls.
class _KaraokeFloatingPill extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final double pillRadius;
  final bool isCompact;
  final bool isPreview;
  final bool customGlow;
  final PulsrPalette palette;

  const _KaraokeFloatingPill({
    required this.props,
    required this.activeColor,
    required this.pillRadius,
    required this.isCompact,
    required this.isPreview,
    required this.customGlow,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final surface = context.playerSurfacePalette;
    final state = props.state;
    final cubit = props.cubit;
    final l10n = context.l10n;
    final allowBlur = !isPreview && AppBlur.canBlur(context);
    final sigma = AppBlur.clampSigma(AppBlur.dock);
    final clampedRadius = pillRadius.clamp(12.0, 36.0);
    final corners = AppRadii.circular(clampedRadius);

    final Color glassFill = p.isDark
        ? Color.alphaBlend(
            activeColor.withValues(alpha: allowBlur ? 0.10 : 0.14),
            p.surfaceContainer.withValues(
              alpha: allowBlur ? 0.72 : AppBlur.solidFallbackMinAlpha,
            ),
          )
        : Color.alphaBlend(
            activeColor.withValues(alpha: 0.06),
            p.surface.withValues(
              alpha: allowBlur ? 0.80 : AppBlur.solidFallbackMinAlpha,
            ),
          );

    final Color borderColor = p.hairline;

    final repeatLabel = state.repeatMode == PlayerRepeatMode.one
        ? l10n.repeatOne
        : state.repeatMode == PlayerRepeatMode.all
            ? l10n.repeatAll
            : l10n.repeatOff;
    final repeatIcon = state.repeatMode == PlayerRepeatMode.one
        ? Icons.repeat_one_rounded
        : Icons.repeat_rounded;
    final shuffleLabel =
        state.isShuffle ? l10n.disableShuffle : l10n.enableShuffle;

    Widget pillContent = Container(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.sm,
        isCompact ? AppSpacing.xxs : AppSpacing.xs,
        AppSpacing.sm,
        isCompact ? AppSpacing.xxs : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: glassFill,
        borderRadius: corners,
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: surface.shadowAt(p.isDark ? 0.36 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          if (customGlow)
            BoxShadow(
              color: activeColor.withValues(alpha: 0.26),
              blurRadius: 28,
              spreadRadius: -2,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slim interactive progress bar driven solely by position BlocSelector
          _KaraokeSlimProgressBar(
            duration: state.duration,
            activeColor: activeColor,
            isPlaying: state.isPlaying,
            isBuffering: state.isBuffering,
            isCompact: isCompact,
            onSeek: cubit.seek,
          ),
          // Compact transport row (all >= 48dp hit targets)
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                PlayerIconActionButton(
                  icon: Icons.shuffle_rounded,
                  tooltip: shuffleLabel,
                  isActive: state.isShuffle,
                  activeColor: activeColor,
                  iconColor: p.textSecondary,
                  iconSize: 19,
                  showActiveDot: true,
                  onTap: cubit.toggleShuffle,
                ),
                PlayerIconActionButton(
                  icon: Icons.skip_previous_rounded,
                  tooltip: l10n.previous,
                  iconColor: state.hasPreviousNeighbour
                      ? p.textPrimary
                      : p.textTertiary.withValues(alpha: 0.4),
                  iconSize: 26,
                  onTap: state.hasPreviousNeighbour ? cubit.previous : null,
                ),
                _KaraokePlayPauseButton(
                  isPlaying: state.isPlaying,
                  activeColor: activeColor,
                  isCompact: isCompact,
                  onTap: cubit.togglePlayPause,
                ),
                PlayerIconActionButton(
                  icon: Icons.skip_next_rounded,
                  tooltip: l10n.next,
                  iconColor: state.hasNextNeighbour
                      ? p.textPrimary
                      : p.textTertiary.withValues(alpha: 0.4),
                  iconSize: 26,
                  onTap: state.hasNextNeighbour ? cubit.next : null,
                ),
                PlayerIconActionButton(
                  icon: repeatIcon,
                  tooltip: repeatLabel,
                  isActive: state.repeatMode != PlayerRepeatMode.off,
                  activeColor: activeColor,
                  iconColor: p.textSecondary,
                  iconSize: 19,
                  showActiveDot: true,
                  onTap: cubit.toggleRepeat,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (allowBlur) {
      pillContent = ClipRRect(
        borderRadius: corners,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: pillContent,
        ),
      );
    }

    return pillContent;
  }
}

class _KaraokePlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final Color activeColor;
  final bool isCompact;
  final VoidCallback onTap;

  const _KaraokePlayPauseButton({
    required this.isPlaying,
    required this.activeColor,
    required this.isCompact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final double size = isCompact ? AppSpacing.minTouchTarget : 52.0;

    return Semantics(
      button: true,
      label: isPlaying ? l10n.pause : l10n.play,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: activeColor,
          boxShadow: [
            BoxShadow(
              color: activeColor.withValues(alpha: 0.36),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: AppColors.fadeStopTransparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              PulsrHaptics.lightImpact();
              onTap();
            },
            child: Center(
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 28,
                color: AppColors.textOnAccent(activeColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Interactive ultra-slim progress bar scoped strictly to
/// `BlocSelector<PlayerCubit, PlayerState, Duration>`.
class _KaraokeSlimProgressBar extends StatefulWidget {
  final Duration duration;
  final Color activeColor;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompact;
  final ValueChanged<Duration> onSeek;

  const _KaraokeSlimProgressBar({
    required this.duration,
    required this.activeColor,
    required this.isPlaying,
    required this.isBuffering,
    required this.isCompact,
    required this.onSeek,
  });

  @override
  State<_KaraokeSlimProgressBar> createState() =>
      _KaraokeSlimProgressBarState();
}

class _KaraokeSlimProgressBarState extends State<_KaraokeSlimProgressBar> {
  double? _dragMs;

  Duration _clampDuration(Duration d) {
    if (d < Duration.zero) return Duration.zero;
    if (d > widget.duration) return widget.duration;
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;

    return BlocSelector<PlayerCubit, PlayerState, Duration>(
      selector: (s) => s.position,
      builder: (context, position) {
        final double maxMs = widget.duration.inMilliseconds.toDouble();
        final double safeMax = maxMs > 0 ? maxMs : 1.0;
        final double effectiveMs =
            (_dragMs ?? position.inMilliseconds.toDouble()).clamp(0.0, safeMax);
        final Duration displayPos = _dragMs != null
            ? Duration(milliseconds: _dragMs!.round())
            : position;

        String formatPair(Duration d) =>
            '${Formatters.formatDuration(d)} / ${Formatters.formatDuration(widget.duration)}';

        final Color inactiveTrack = p.isDark
            ? AppColors.specularAt(0.18)
            : p.textPrimary.withValues(alpha: 0.14);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Formatters.formatDuration(displayPos),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: _dragMs != null ? widget.activeColor : p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Semantics(
                  slider: true,
                  label: l10n.seekLabel,
                  value: formatPair(displayPos),
                  increasedValue: formatPair(
                    _clampDuration(displayPos + const Duration(seconds: 10)),
                  ),
                  decreasedValue: formatPair(
                    _clampDuration(displayPos - const Duration(seconds: 10)),
                  ),
                  onIncrease: widget.isBuffering
                      ? null
                      : () => widget.onSeek(
                            _clampDuration(
                              displayPos + const Duration(seconds: 10),
                            ),
                          ),
                  onDecrease: widget.isBuffering
                      ? null
                      : () => widget.onSeek(
                            _clampDuration(
                              displayPos - const Duration(seconds: 10),
                            ),
                          ),
                  excludeSemantics: true,
                  child: SizedBox(
                    height: widget.isCompact ? 26.0 : 30.0,
                    child: PulsrSlider(
                      value: effectiveMs,
                      min: 0.0,
                      max: safeMax,
                      height: widget.isCompact ? 26.0 : 30.0,
                      activeColor: widget.activeColor,
                      inactiveColor: inactiveTrack,
                      thumbColor: widget.activeColor,
                      sliderStyle: PlayerSliderStyle.capsule,
                      isWavy: false,
                      animateWave: false,
                      onChangeStart: widget.isBuffering
                          ? null
                          : (val) {
                              PulsrHaptics.selectionClick();
                              setState(() => _dragMs = val);
                            },
                      onChanged: widget.isBuffering
                          ? (_) {}
                          : (val) => setState(() => _dragMs = val),
                      onChangeEnd: widget.isBuffering
                          ? null
                          : (val) {
                              widget.onSeek(Duration(milliseconds: val.round()));
                              setState(() => _dragMs = null);
                            },
                      onChangeCancel: () => setState(() => _dragMs = null),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Formatters.formatDuration(widget.duration),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
