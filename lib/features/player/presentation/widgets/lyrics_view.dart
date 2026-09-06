// lib/features/player/presentation/widgets/lyrics_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/lrc_parser.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

class LyricsView extends StatefulWidget {
  /// Playback position used to highlight the active line.
  ///
  /// Optional: when null (preferred usage from player themes), the view derives
  /// position ticks from [PlayerCubit] and forwards them to [LyricController].
  final Duration? currentPosition;
  final List<LyricsLine> lyrics;
  final bool isLoading;
  final Color activeColor;
  final LyricsSource source;
  final ValueChanged<Duration>? onLineTapped;

  const LyricsView({
    super.key,
    this.currentPosition,
    required this.lyrics,
    this.isLoading = false,
    this.activeColor = Colors.white,
    this.source = LyricsSource.none,
    this.onLineTapped,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late final LyricController _lyricController;
  Duration _audibleOffset = Duration.zero;

  // Cached synced check
  List<LyricsLine>? _syncedCheckSource;
  bool _syncedCache = false;

  bool get _isSynced {
    if (!identical(_syncedCheckSource, widget.lyrics)) {
      _syncedCheckSource = widget.lyrics;
      _syncedCache =
          widget.lyrics.any((line) => line.timestamp > Duration.zero);
    }
    return _syncedCache;
  }

  LyricsSource get _effectiveSource {
    if (widget.source != LyricsSource.none) return widget.source;
    if (widget.lyrics.isNotEmpty) return widget.lyrics.first.source;
    return LyricsSource.none;
  }

  @override
  void initState() {
    super.initState();
    _lyricController = LyricController();
    _setupTapCallback();
    _syncLyricsToController();
  }

  void _setupTapCallback() {
    _lyricController.setOnTapLineCallback((position) {
      HapticFeedback.selectionClick();
      if (widget.onLineTapped != null) {
        widget.onLineTapped!(position);
      } else {
        try {
          context.read<PlayerCubit>().seek(position);
        } catch (_) {}
      }
    });
  }

  void _syncLyricsToController() {
    if (widget.lyrics.isEmpty) {
      _lyricController.loadLyric('');
      return;
    }

    if (_isSynced) {
      final lrc = LrcParser.formatToLrc(widget.lyrics);
      _lyricController.loadLyric(lrc);

      // Initial progress update if available
      if (widget.currentPosition != null) {
        _updateProgress(widget.currentPosition!);
      }
    }
  }

  void _updateProgress(Duration position) {
    final effectivePos = position - _audibleOffset;
    _lyricController.setProgress(
      effectivePos < Duration.zero ? Duration.zero : effectivePos,
    );
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(widget.lyrics, oldWidget.lyrics) ||
        widget.lyrics.length != oldWidget.lyrics.length) {
      _syncLyricsToController();
    }

    if (widget.currentPosition != null &&
        widget.currentPosition != oldWidget.currentPosition) {
      _updateProgress(widget.currentPosition!);
    }
  }

  @override
  void dispose() {
    _lyricController.dispose();
    super.dispose();
  }

  Widget _buildSourceBadge(LyricsSource source) {
    if (source == LyricsSource.none) return const SizedBox.shrink();

    final String label = switch (source) {
      LyricsSource.embedded => 'Embedded',
      LyricsSource.externalLrc => 'LRC File',
      LyricsSource.lrclib => 'LRCLIB Synced',
      LyricsSource.ytmusic => 'YouTube Music',
      LyricsSource.none => '',
    };
    final IconData icon = switch (source) {
      LyricsSource.embedded => Icons.music_note,
      LyricsSource.externalLrc => Icons.subtitles_outlined,
      LyricsSource.lrclib => Icons.cloud_done_rounded,
      LyricsSource.ytmusic => Icons.lyrics_rounded,
      LyricsSource.none => Icons.music_note,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: widget.activeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.activeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: widget.activeColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: widget.activeColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlainTextList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      itemCount: widget.lyrics.length,
      itemBuilder: (context, index) {
        final line = widget.lyrics[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            line.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSyncedLyricView() {
    final style = LyricStyles.default1.copyWith(
      textStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Colors.white.withValues(alpha: 0.45),
        height: 1.4,
      ),
      activeStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: widget.activeColor,
        height: 1.3,
        shadows: [
          Shadow(
            color: widget.activeColor.withValues(alpha: 0.4),
            blurRadius: 16,
          ),
        ],
      ),
      activeHighlightColor: widget.activeColor,
      textAlign: TextAlign.center,
      lineGap: 20,
      anchorPosition: 0.42,
      activeAnchorPosition: 0.42,
      fadeRange: FadeRange(top: 36, bottom: 36),
      selectLineResumeDuration: const Duration(seconds: 2),
      activeLineResumeDuration: const Duration(seconds: 4),
      scrollDuration: const Duration(milliseconds: 300),
      enableSwitchAnimation: true,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: LyricView(
            controller: _lyricController,
            style: style,
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    final source = _effectiveSource;
    final isSynced = _isSynced;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: AppRadii.cardRadius,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: isSynced ? _buildSyncedLyricView() : _buildPlainTextList(),
          ),
          if (source != LyricsSource.none)
            Positioned(
              top: 12,
              right: 12,
              child: IgnorePointer(
                child: _buildSourceBadge(source),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    try {
      _audibleOffset = context
          .select<SettingsCubit, Duration>((c) => c.state.audibleLatencyOffset);
    } catch (_) {
      _audibleOffset = Duration.zero;
    }

    if (widget.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: widget.activeColor),
      );
    }

    if (widget.lyrics.isEmpty) {
      String noLyricsText = 'No lyrics found';
      try {
        noLyricsText = context.l10n.noLyricsFound;
      } catch (_) {}

      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_outlined, size: 48, color: p.textTertiary),
              const SizedBox(height: 12),
              Text(
                noLyricsText,
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Place a .lrc file in the same folder as your audio track or embed lyrics into file tags.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: p.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  try {
                    context.read<PlayerCubit>().refreshLyrics();
                  } catch (_) {}
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Search Lyrics',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.activeColor,
                  side: BorderSide(
                      color: widget.activeColor.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // When currentPosition is not explicitly passed, listen to PlayerCubit position ticks
    if (widget.currentPosition == null) {
      try {
        context.read<PlayerCubit>();
        return BlocListener<PlayerCubit, PlayerState>(
          listenWhen: (previous, current) =>
              previous.position != current.position,
          listener: (context, state) {
            _updateProgress(state.position);
          },
          child: _buildContent(),
        );
      } catch (_) {
        return _buildContent();
      }
    }

    return _buildContent();
  }
}
