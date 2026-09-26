import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/lrc_parser.dart';
import '../../../../data/lyrics/lyrics_offset_store.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'karaoke_mode_screen.dart';
import 'lyrics_editor_sheet.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/utils/error_logger.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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

  // Per-file manual sync correction, persisted via [LyricsOffsetStore].
  final LyricsOffsetStore _offsetStore = LyricsOffsetStore();
  int _manualOffsetMs = 0;
  String? _offsetSongPath;

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
        } catch (e, st) {
          ErrorLogger.log('Lyrics tap seek failed',
              error: e, stackTrace: st, category: 'Lyrics');
        }
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

      // Push current position immediately so highlight appears without waiting
      // for the next 200ms tick. Works for both explicit currentPosition and
      // BlocListener-driven mode.
      Duration? pos = widget.currentPosition;
      if (pos == null) {
        try {
          pos = context.read<PlayerCubit>().state.position;
        } catch (e, st) {
          ErrorLogger.log('Lyrics reading PlayerCubit position failed',
              error: e, stackTrace: st, category: 'Lyrics');
        }
      }
      if (pos != null) {
        // Defer one frame so LyricController finishes internal parse.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateProgress(pos!);
        });
      }
    } else {
      // Plain-text lyrics: clear synced controller so stale synced data
      // doesn't leak when switching between synced/plain.
      _lyricController.loadLyric('');
    }
  }

  void _updateProgress(Duration position) {
    final manualOffset = Duration(milliseconds: _manualOffsetMs);
    final effective = (position - _audibleOffset - manualOffset);
    _lyricController.setProgress(effective.isNegative ? Duration.zero : effective);
  }

  /// Loads the persisted per-file offset when the current song changes.
  void _syncManualOffset(String? path) {
    if (path == _offsetSongPath) return;
    _offsetSongPath = path;
    if (path == null || path.isEmpty) {
      _applyManualOffset(0);
      return;
    }
    _offsetStore.getOffsetMs(path).catchError((e, st) {
      ErrorLogger.log('Failed to load lyrics manual offset for $path',
          error: e, stackTrace: st, category: 'Lyrics');
      return 0;
    }).then((ms) {
      if (!mounted || _offsetSongPath != path) return;
      _offsetSongPath = path;
      _applyManualOffset(ms);
    });
  }

  void _applyManualOffset(int ms) {
    if (ms == _manualOffsetMs) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _manualOffsetMs = ms);
      Duration? pos = widget.currentPosition;
      if (pos == null) {
        try {
          pos = context.read<PlayerCubit>().state.position;
        } catch (e, st) {
          ErrorLogger.log(
              'PlayerCubit unavailable for manual offset position',
              error: e,
              stackTrace: st,
              category: 'Lyrics');
        }
      }
      if (pos != null) _updateProgress(pos);
    });
  }

  Future<void> _adjustManualOffset(int deltaMs) async {
    final path = _offsetSongPath;
    if (path == null || path.isEmpty) return;
    final next = (_manualOffsetMs + deltaMs).clamp(-5000, 5000);
    _applyManualOffset(next);
    await _offsetStore.setOffsetMs(path, next);
  }

  Future<void> _resetManualOffset() async {
    final path = _offsetSongPath;
    _applyManualOffset(0);
    if (path != null && path.isNotEmpty) {
      await _offsetStore.clearOffset(path);
    }
  }

  Future<void> _showOffsetSheet() async {
    final l10n = context.l10n;
    await PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          return Container(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.lg, AppSpacing.s20, AppSpacing.lg, AppSpacing.s28),
            decoration: BoxDecoration(
              color: Theme.of(sheetContext).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(AppRadii.r20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.settingsSyncOffset,
                  style: const TextStyle(
                      fontSize: AppFontSize.bodyLarge, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${_manualOffsetMs >= 0 ? '+' : ''}$_manualOffsetMs ms',
                  style: TextStyle(
                    fontSize: AppFontSize.display,
                    fontWeight: FontWeight.w800,
                    color: widget.activeColor,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        await _adjustManualOffset(-50);
                        setSheet(() {});
                      },
                      child: const Text('-50 ms'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    OutlinedButton(
                      onPressed: () async {
                        await _adjustManualOffset(50);
                        setSheet(() {});
                      },
                      child: const Text('+50 ms'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                TextButton.icon(
                  onPressed: () async {
                    await _resetManualOffset();
                    setSheet(() {});
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: Text(l10n.reset),
                ),
                const SizedBox(height: AppSpacing.xxs),
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(l10n.done),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only reload the controller when the lyrics content or source actually changed,
    // avoiding re-parsing and animation resets caused by Freezed state emissions.
    final lyricsChanged = widget.source != oldWidget.source ||
        (!identical(widget.lyrics, oldWidget.lyrics) &&
            (widget.lyrics.length != oldWidget.lyrics.length ||
                !listEquals(widget.lyrics, oldWidget.lyrics)));
    if (lyricsChanged) {
      _syncLyricsToController();
    }

    if (widget.currentPosition != null &&
        widget.currentPosition != oldWidget.currentPosition) {
      _updateProgress(widget.currentPosition!);
    } else if (lyricsChanged) {
      Duration? pos = widget.currentPosition;
      if (pos == null) {
        try {
          pos = context.read<PlayerCubit>().state.position;
        } catch (_) {}
      }
      if (pos != null) _updateProgress(pos);
    }
  }

  @override
  void dispose() {
    _lyricController.dispose();
    super.dispose();
  }

  Widget _buildSourceBadge(LyricsSource source, bool synced) {
    if (source == LyricsSource.none) return const SizedBox.shrink();

    final String label = switch (source) {
      LyricsSource.embedded =>
        synced ? context.l10n.dspEmbedded : context.l10n.dspEmbeddedUnsynced,
      LyricsSource.externalLrc => 'LRC File',
      LyricsSource.lrclib => synced ? context.l10n.dspLrcLibSynced : 'LRCLIB',
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: widget.activeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.r12),
        border: Border.all(
          color: widget.activeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: widget.activeColor),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: TextStyle(
              color: widget.activeColor,
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w600,
              letterSpacing: AppTracking.medium,
            ),
          ),
        ],
      ),
    );
  }

  void _openKaraoke() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const KaraokeModeScreen(),
      ),
    );
  }

  Future<void> _openEditor() async {
    final PlayerCubit cubit;
    try {
      cubit = context.read<PlayerCubit>();
    } catch (_) {
      return;
    }
    final song = cubit.state.currentSong;
    if (song == null) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => LyricsEditorSheet(
        song: song,
        currentPosition: cubit.state.position,
        initialLyrics: cubit.state.lyrics,
        onSave: (lines) async {
          final persisted = await cubit.updateLyrics(lines);
          messenger?.showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(persisted
                ? l10n.dspLyricsSaved
                : l10n.dspLyricsSessionOnly),
          ));
        },
      ),
    );
  }

  Widget _headerIconButton(
      IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, color: widget.activeColor, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: AppSpacing.minTouchTarget,
        minHeight: AppSpacing.minTouchTarget,
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildHeaderActions() {
    PlayerCubit? cubit;
    try {
      cubit = context.read<PlayerCubit>();
    } catch (_) {}
    final hasSong = cubit?.state.currentSong != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasSong)
          _headerIconButton(
              Icons.sync_rounded, context.l10n.settingsSyncOffset,
              () => unawaited(_showOffsetSheet())),
        if (hasSong)
          _headerIconButton(
              Icons.edit_note_rounded, context.l10n.dspEditLyrics, _openEditor),
        _headerIconButton(
            Icons.fullscreen_rounded, context.l10n.dspKaraokeMode, _openKaraoke),
      ],
    );
  }

  Widget _buildPlainTextList(PulsrPalette p) {
    return ListView.builder(
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.s20),
      itemCount: widget.lyrics.length,
      itemBuilder: (context, index) {
        final line = widget.lyrics[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
          child: Text(
            line.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFontSize.bodyLarge,
              fontWeight: FontWeight.w500,
              color: p.textPrimary,
              height: 1.4,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSyncedLyricView(PulsrPalette p) {
    final activeCol =
        widget.activeColor == Colors.white ? p.accent : widget.activeColor;
    final style = LyricStyles.default1.copyWith(
      textStyle: TextStyle(
        fontSize: AppFontSize.bodyLarge,
        fontWeight: FontWeight.w500,
        color: p.textSecondary.withValues(alpha: 0.7),
        height: 1.4,
      ),
      activeStyle: TextStyle(
        fontSize: AppFontSize.titleLarge,
        fontWeight: FontWeight.w800,
        color: activeCol,
        height: 1.3,
        shadows: [
          Shadow(
            color: activeCol.withValues(alpha: 0.4),
            blurRadius: 16,
          ),
        ],
      ),
      activeHighlightColor: activeCol,
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

    return RepaintBoundary(
      child: LayoutBuilder(
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
      ),
    );
  }

  Widget _buildContent() {
    final source = _effectiveSource;
    final isSynced = _isSynced;
    final p = context.palette;

    return Container(
      decoration: BoxDecoration(
        // Lyrics scrim uses palette background token to support AMOLED and light mode cleanly.
        color: p.bg.withValues(alpha: p.isDark ? 0.40 : 0.72),
        borderRadius: AppRadii.cardRadius,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxl),
            child: isSynced ? _buildSyncedLyricView(p) : _buildPlainTextList(p),
          ),
          PositionedDirectional(
            top: 4,
            start: 4,
            child: _buildHeaderActions(),
          ),
          if (source != LyricsSource.none)
            PositionedDirectional(
              top: 12,
              end: 12,
              child: IgnorePointer(
                child: _buildSourceBadge(source, isSynced),
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
    try {
      final songKey = context.select<PlayerCubit, String?>((c) {
        final s = c.state.currentSong;
        if (s == null) return null;
        if (s.path.isNotEmpty) return s.path;
        if (s.remoteId != null && s.remoteId!.isNotEmpty) return s.remoteId;
        return 'song_${s.id}';
      });
      _syncManualOffset(songKey);
    } catch (_) {}

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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_outlined, size: 48, color: p.textTertiary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                noLyricsText,
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: AppFontSize.bodyLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(context.l10n.placeLrcHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: p.textSecondary, fontSize: AppFontSize.bodySmall, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () {
                  try {
                    context.read<PlayerCubit>().refreshLyrics();
                  } catch (_) {}
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(context.l10n.searchLyrics,
                    style: TextStyle(fontSize: AppFontSize.label)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.activeColor,
                  side: BorderSide(
                      color: widget.activeColor.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget content = _buildContent();

    // Listen to latency offset updates directly so offset slider reacts immediately while paused
    try {
      context.read<SettingsCubit>();
      content = BlocListener<SettingsCubit, SettingsState>(
        listenWhen: (prev, curr) =>
            prev.audibleLatencyOffset != curr.audibleLatencyOffset,
        listener: (context, settingsState) {
          _audibleOffset = settingsState.audibleLatencyOffset;
          Duration? curPos = widget.currentPosition;
          if (curPos == null) {
            try {
              curPos = context.read<PlayerCubit>().state.position;
            } catch (_) {}
          }
          if (curPos != null) {
            _updateProgress(curPos);
          }
        },
        child: content,
      );
    } catch (_) {}

    // When currentPosition is not explicitly passed, listen to PlayerCubit position ticks
    if (widget.currentPosition == null) {
      try {
        // Resolve the provider inside the guard: the BlocListener only looks it
        // up during mount (outside this try), so without this probe a missing
        // PlayerCubit would throw ProviderNotFoundException.
        context.read<PlayerCubit>();
        content = BlocListener<PlayerCubit, PlayerState>(
          listenWhen: (previous, current) {
            if (!_isSynced) return false;
            return previous.position != current.position ||
                previous.currentSong?.id != current.currentSong?.id;
          },
          listener: (context, state) {
            _updateProgress(state.position);
          },
          child: content,
        );
      } catch (_) {}
    }

    return content;
  }
}
