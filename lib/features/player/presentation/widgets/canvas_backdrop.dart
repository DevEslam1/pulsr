// lib/features/player/presentation/widgets/canvas_backdrop.dart
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../data/db/app_database.dart';
import '../../../../services/canvas/canvas_repository.dart';
import '../../../settings/cubit/settings_cubit.dart';

/// Looped video backdrop for Spotify Canvas, Apple Music motion artwork,
/// and Tidal video covers.
///
/// Features:
/// - Smooth video loop via [VideoPlayerController] (muted audio).
/// - 400ms fade-in transition when ready, keeping album art underneath.
/// - Synchronizes play/pause state with playback transport.
/// - Dual placement: full-screen blurred ambient backdrop or inside album art card.
class CanvasBackdrop extends StatefulWidget {
  final SongsTableData? song;
  final bool isPlaying;
  final bool isBackdropMode;
  final Widget? fallbackArtwork;
  final BorderRadius? borderRadius;
  final double blurSigma;
  final CanvasRepository? repository;

  const CanvasBackdrop({
    super.key,
    required this.song,
    required this.isPlaying,
    this.isBackdropMode = false,
    this.fallbackArtwork,
    this.borderRadius,
    this.blurSigma = 28.0,
    this.repository,
  });

  @override
  State<CanvasBackdrop> createState() => _CanvasBackdropState();
}

class _CanvasBackdropState extends State<CanvasBackdrop> {
  CanvasRepository get _repository =>
      widget.repository ?? CanvasRepository.instance;

  VideoPlayerController? _controller;
  CanvasArtwork? _canvas;
  CanvasArtwork? get canvas => _canvas;
  bool _isRendered = false;
  int? _resolvedSongId;

  @override
  void initState() {
    super.initState();
    _resolveAndLoad(widget.song);
  }

  @override
  void didUpdateWidget(CanvasBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.song?.id != oldWidget.song?.id) {
      _resolveAndLoad(widget.song);
    } else if (widget.isPlaying != oldWidget.isPlaying) {
      _syncPlayState();
    }
  }

  void _syncPlayState() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (widget.isPlaying) {
      if (!controller.value.isPlaying) controller.play();
    } else {
      if (controller.value.isPlaying) controller.pause();
    }
  }

  Future<void> _resolveAndLoad(SongsTableData? song) async {
    final songId = song?.id;
    _resolvedSongId = songId;

    await _disposeController();
    if (!mounted) return;

    setState(() {
      _canvas = null;
      _isRendered = false;
    });

    if (song == null) return;

    // Fast check from memory cache
    CanvasArtwork? artwork = _repository.cached(song);
    artwork ??= await _repository.canvasFor(song);

    if (!mounted || _resolvedSongId != songId) return;

    if (artwork != null) {
      setState(() => _canvas = artwork);
      await _initializeController(artwork, songId);
    }
  }

  Future<void> _initializeController(CanvasArtwork canvas, int? songId) async {
    try {
      VideoPlayerController controller;
      final local = canvas.localFilePath;
      if (local != null && File(local).existsSync()) {
        controller = VideoPlayerController.file(File(local));
      } else {
        controller =
            VideoPlayerController.networkUrl(Uri.parse(canvas.videoUrl));
      }

      await controller.initialize();
      await controller.setLooping(true);
      await controller
          .setVolume(0.0); // Never emit sound to avoid interrupting music

      if (!mounted || _resolvedSongId != songId) {
        await controller.dispose();
        return;
      }

      _controller = controller;

      if (widget.isPlaying) {
        await controller.play();
      }

      if (mounted) {
        setState(() => _isRendered = true);
      }
    } catch (e, st) {
      ErrorLogger.log('Canvas VideoPlayerController initialization failed',
          error: e, stackTrace: st, category: 'CanvasBackdrop');
      if (mounted) {
        setState(() => _isRendered = false);
      }
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.pause();
        await controller.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvasEnabled = context.select<SettingsCubit, bool>(
      (c) => c.state.canvasEnabled,
    );

    final showVideo = canvasEnabled &&
        _controller != null &&
        _controller!.value.isInitialized &&
        _isRendered;

    if (widget.isBackdropMode) {
      return _buildFullScreenBackdrop(showVideo);
    } else {
      return _buildCardContent(showVideo);
    }
  }

  Widget _buildFullScreenBackdrop(bool showVideo) {
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Underlying fallback artwork / placeholder
          if (widget.fallbackArtwork != null) widget.fallbackArtwork!,

          // 400ms smooth fade-in video layer with ambient blur
          if (_controller != null && _controller!.value.isInitialized)
            AnimatedOpacity(
              opacity: showVideo ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: widget.blurSigma,
                  sigmaY: widget.blurSigma,
                ),
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: _controller!.value.size.width > 0
                        ? _controller!.value.size.width
                        : 720,
                    height: _controller!.value.size.height > 0
                        ? _controller!.value.size.height
                        : 1280,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),
            ),

          // Ambient dark vignette scrim so text and controls remain crisp
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.40),
                  Colors.black.withValues(alpha: 0.60),
                  Colors.black.withValues(alpha: 0.82),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.50, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardContent(bool showVideo) {
    final radius = widget.borderRadius ?? AppRadii.r28All;

    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Underneath fallback artwork placeholder
          if (widget.fallbackArtwork != null) widget.fallbackArtwork!,

          // 2. 400ms smooth fade-in looped video
          if (_controller != null && _controller!.value.isInitialized)
            AnimatedOpacity(
              opacity: showVideo ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _controller!.value.size.width > 0
                      ? _controller!.value.size.width
                      : 720,
                  height: _controller!.value.size.height > 0
                      ? _controller!.value.size.height
                      : 720,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact chip / button for Now Playing to toggle Canvas playback on/off.
class CanvasToggleChip extends StatelessWidget {
  final Color activeColor;
  final bool compact;

  const CanvasToggleChip({
    super.key,
    required this.activeColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isCanvasEnabled = context.select<SettingsCubit, bool>(
      (c) => c.state.canvasEnabled,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          final next = !isCanvasEnabled;
          context.read<SettingsCubit>().toggleCanvasEnabled(next);
          PulsrToast.show(
            context,
            message:
                next ? 'Canvas & Motion Artwork enabled' : 'Canvas disabled',
            icon: next
                ? Icons.motion_photos_on_rounded
                : Icons.motion_photos_off_rounded,
          );
        },
        borderRadius: AppRadii.r20All,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 3 : 5,
          ),
          decoration: BoxDecoration(
            color: isCanvasEnabled
                ? activeColor.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: AppRadii.r20All,
            border: Border.all(
              color: isCanvasEnabled
                  ? activeColor.withValues(alpha: 0.50)
                  : Colors.white.withValues(alpha: 0.15),
              width: 1.0,
            ),
            boxShadow: isCanvasEnabled
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCanvasEnabled
                    ? Icons.motion_photos_on_rounded
                    : Icons.motion_photos_off_rounded,
                size: compact ? 13 : 15,
                color: isCanvasEnabled ? activeColor : Colors.white60,
              ),
              const SizedBox(width: 4),
              Text(
                'CANVAS',
                style: TextStyle(
                  fontSize: compact ? 9.5 : 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: isCanvasEnabled ? activeColor : Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
