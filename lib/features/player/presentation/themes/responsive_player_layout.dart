import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../../../../core/utils/adaptive.dart';

/// Distinct player layout modes across screen sizes and orientations.
enum PlayerLayoutMode {
  compactPortrait,
  compactLandscape,
  mediumPortrait,
  mediumLandscape,
  expandedLarge;

  bool get isLandscape =>
      this == PlayerLayoutMode.compactLandscape ||
      this == PlayerLayoutMode.mediumLandscape ||
      this == PlayerLayoutMode.expandedLarge;

  bool get isTwoPane => isLandscape;
}

/// Comprehensive responsive metrics for player themes.
class PlayerLayoutMetrics {
  final BoxConstraints constraints;
  final PulsrBreakpoint breakpoint;
  final Orientation orientation;
  final PlayerLayoutMode layoutMode;

  /// Artwork box dimension (width and height for 1:1 aspect ratio).
  final double artworkSize;

  /// Touch-safe main play/pause button size.
  final double playPauseButtonSize;

  /// Touch-safe secondary control button size (previous, next, shuffle, repeat).
  final double secondaryButtonSize;

  /// Touch target height for seek bar scrubber (visual track is thinner).
  final double seekBarTouchHeight;

  /// Maximum content constraint width for portrait layouts.
  final double maxContentWidth;

  /// Vertical spacing between track info and seek bar.
  final double spacingTrackToSeek;

  /// Vertical spacing between seek bar and controls.
  final double spacingSeekToControls;

  /// Vertical spacing between controls and bottom dock/switcher.
  final double spacingControlsToBottom;

  /// Horizontal padding for player content.
  final double horizontalPadding;

  const PlayerLayoutMetrics({
    required this.constraints,
    required this.breakpoint,
    required this.orientation,
    required this.layoutMode,
    required this.artworkSize,
    required this.playPauseButtonSize,
    required this.secondaryButtonSize,
    required this.seekBarTouchHeight,
    required this.maxContentWidth,
    required this.spacingTrackToSeek,
    required this.spacingSeekToControls,
    required this.spacingControlsToBottom,
    required this.horizontalPadding,
  });

  factory PlayerLayoutMetrics.of(
      BuildContext context, BoxConstraints constraints) {
    final breakpoint = context.breakpoint;
    final isLandscape = context.isLandscape;
    final orientation = MediaQuery.orientationOf(context);

    final PlayerLayoutMode layoutMode;
    if (breakpoint.isCompact) {
      layoutMode = isLandscape
          ? PlayerLayoutMode.compactLandscape
          : PlayerLayoutMode.compactPortrait;
    } else if (breakpoint.isMedium) {
      layoutMode = isLandscape
          ? PlayerLayoutMode.mediumLandscape
          : PlayerLayoutMode.mediumPortrait;
    } else {
      layoutMode = PlayerLayoutMode.expandedLarge;
    }

    final double availableWidth = constraints.maxWidth;
    final double availableHeight = constraints.maxHeight;

    final double artworkSize;
    final double horizontalPadding;
    final double maxContentWidth;

    if (layoutMode == PlayerLayoutMode.compactLandscape) {
      // Landscape phone: side-by-side; artwork takes ~40-45% of width, bounded by height
      final maxArtByHeight = availableHeight - 48.0;
      final maxArtByWidth = availableWidth * 0.42;
      artworkSize = math.max(
          120.0, math.min(maxArtByHeight, math.min(maxArtByWidth, 280.0)));
      horizontalPadding = 16.0;
      maxContentWidth = double.infinity;
    } else if (layoutMode == PlayerLayoutMode.mediumLandscape) {
      // Medium landscape: artwork left, controls right
      final maxArtByHeight = availableHeight - 64.0;
      final maxArtByWidth = availableWidth * 0.45;
      artworkSize = math.max(
          180.0, math.min(maxArtByHeight, math.min(maxArtByWidth, 380.0)));
      horizontalPadding = 24.0;
      maxContentWidth = 900.0;
    } else if (layoutMode == PlayerLayoutMode.expandedLarge) {
      // Large tablet / desktop
      final maxArtByHeight = availableHeight - 80.0;
      final maxArtByWidth = availableWidth * 0.42;
      artworkSize = math.max(
          240.0, math.min(maxArtByHeight, math.min(maxArtByWidth, 480.0)));
      horizontalPadding = 32.0;
      maxContentWidth = 1100.0;
    } else if (layoutMode == PlayerLayoutMode.mediumPortrait) {
      // Medium portrait (small tablet or foldable unfolded portrait)
      artworkSize = math.min(availableWidth - 96.0, 420.0);
      horizontalPadding = 32.0;
      maxContentWidth = 560.0;
    } else {
      // Compact portrait (phone portrait)
      artworkSize = math.min(availableWidth - 48.0, 360.0);
      horizontalPadding = 20.0;
      maxContentWidth = double.infinity;
    }

    final double heightRatio = (availableHeight / 720.0).clamp(0.6, 1.2);

    final double playPauseButtonSize =
        breakpoint >= PulsrBreakpoint.medium ? 64.0 : 56.0;
    final double secondaryButtonSize = 48.0; // Guaranteed >= 48dp touch target
    final double seekBarTouchHeight = 48.0;

    final double spacingTrackToSeek =
        (breakpoint >= PulsrBreakpoint.medium ? 12.0 : 8.0) * heightRatio;
    final double spacingSeekToControls =
        (breakpoint >= PulsrBreakpoint.medium ? 14.0 : 10.0) * heightRatio;
    final double spacingControlsToBottom =
        (breakpoint >= PulsrBreakpoint.medium ? 12.0 : 8.0) * heightRatio;

    return PlayerLayoutMetrics(
      constraints: constraints,
      breakpoint: breakpoint,
      orientation: orientation,
      layoutMode: layoutMode,
      artworkSize: artworkSize,
      playPauseButtonSize: playPauseButtonSize,
      secondaryButtonSize: secondaryButtonSize,
      seekBarTouchHeight: seekBarTouchHeight,
      maxContentWidth: maxContentWidth,
      spacingTrackToSeek: spacingTrackToSeek,
      spacingSeekToControls: spacingSeekToControls,
      spacingControlsToBottom: spacingControlsToBottom,
      horizontalPadding: horizontalPadding,
    );
  }
}
