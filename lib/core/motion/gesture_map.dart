import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// Surface area where a gesture lives in Pulsr.
enum GestureSurface {
  miniPlayer,
  dock,
  nowPlaying,
  platter,
  waveform,
  lyrics,
}

extension GestureSurfaceL10n on GestureSurface {
  String label(AppLocalizations l10n) => switch (this) {
        GestureSurface.miniPlayer => l10n.gestureSurfaceMiniPlayer,
        GestureSurface.dock => l10n.gestureSurfaceDock,
        GestureSurface.nowPlaying => l10n.gestureSurfaceNowPlaying,
        GestureSurface.platter => l10n.gestureSurfacePlatter,
        GestureSurface.waveform => l10n.gestureSurfaceWaveform,
        GestureSurface.lyrics => l10n.gestureSurfaceLyrics,
      };
}

/// Canonical entry in [PulsrGestureMap].
class PulsrGestureEntry {
  final String id;
  final GestureSurface surface;
  final IconData icon;
  final String Function(AppLocalizations l10n) titleBuilder;
  final String Function(AppLocalizations l10n) descriptionBuilder;

  const PulsrGestureEntry({
    required this.id,
    required this.surface,
    required this.icon,
    required this.titleBuilder,
    required this.descriptionBuilder,
  });
}

/// Single authoritative registry of every interactive gesture across Pulsr.
///
/// Rendered by the "Gestures Guide" sheet from PlayerMoreSheet, Onboarding, and
/// Settings -> Appearance & Gestures.
abstract final class PulsrGestureMap {
  static String _miniHorizTitle(AppLocalizations l10n) =>
      l10n.gestureMiniSwipeHorizTitle;
  static String _miniHorizDesc(AppLocalizations l10n) =>
      l10n.gestureMiniSwipeHorizDesc;

  static String _miniUpTitle(AppLocalizations l10n) =>
      l10n.gestureMiniSwipeUpTitle;
  static String _miniUpDesc(AppLocalizations l10n) =>
      l10n.gestureMiniSwipeUpDesc;

  static String _dockDownTitle(AppLocalizations l10n) =>
      l10n.gestureDockSwipeDownTitle;
  static String _dockDownDesc(AppLocalizations l10n) =>
      l10n.gestureDockSwipeDownDesc;

  static String _artTapTitle(AppLocalizations l10n) =>
      l10n.gestureArtworkTapTitle;
  static String _artTapDesc(AppLocalizations l10n) =>
      l10n.gestureArtworkTapDesc;

  static String _artDoubleTitle(AppLocalizations l10n) =>
      l10n.gestureArtworkDoubleTapTitle;
  static String _artDoubleDesc(AppLocalizations l10n) =>
      l10n.gestureArtworkDoubleTapDesc;

  static String _artSwipeTitle(AppLocalizations l10n) =>
      l10n.gestureArtworkSwipeTitle;
  static String _artSwipeDesc(AppLocalizations l10n) =>
      l10n.gestureArtworkSwipeDesc;

  static String _dismissTitle(AppLocalizations l10n) =>
      l10n.gestureNowPlayingDismissTitle;
  static String _dismissDesc(AppLocalizations l10n) =>
      l10n.gestureNowPlayingDismissDesc;

  static String _platterScrubTitle(AppLocalizations l10n) =>
      l10n.gesturePlatterScrubTitle;
  static String _platterScrubDesc(AppLocalizations l10n) =>
      l10n.gesturePlatterScrubDesc;

  static String _rpmBadgeTitle(AppLocalizations l10n) =>
      l10n.gestureRpmBadgeTitle;
  static String _rpmBadgeDesc(AppLocalizations l10n) =>
      l10n.gestureRpmBadgeDesc;

  static String _waveformPinchTitle(AppLocalizations l10n) =>
      l10n.gestureWaveformPinchTitle;
  static String _waveformPinchDesc(AppLocalizations l10n) =>
      l10n.gestureWaveformPinchDesc;

  static String _lyricsOffsetTitle(AppLocalizations l10n) =>
      l10n.gestureLyricsOffsetTitle;
  static String _lyricsOffsetDesc(AppLocalizations l10n) =>
      l10n.gestureLyricsOffsetDesc;

  static const List<PulsrGestureEntry> entries = [
    PulsrGestureEntry(
      id: 'mini_swipe_horizontal',
      surface: GestureSurface.miniPlayer,
      icon: Icons.swipe_rounded,
      titleBuilder: _miniHorizTitle,
      descriptionBuilder: _miniHorizDesc,
    ),
    PulsrGestureEntry(
      id: 'mini_swipe_up',
      surface: GestureSurface.miniPlayer,
      icon: Icons.swipe_up_rounded,
      titleBuilder: _miniUpTitle,
      descriptionBuilder: _miniUpDesc,
    ),
    PulsrGestureEntry(
      id: 'dock_swipe_down',
      surface: GestureSurface.dock,
      icon: Icons.swipe_down_rounded,
      titleBuilder: _dockDownTitle,
      descriptionBuilder: _dockDownDesc,
    ),
    PulsrGestureEntry(
      id: 'artwork_tap',
      surface: GestureSurface.nowPlaying,
      icon: Icons.touch_app_rounded,
      titleBuilder: _artTapTitle,
      descriptionBuilder: _artTapDesc,
    ),
    PulsrGestureEntry(
      id: 'artwork_double_tap',
      surface: GestureSurface.nowPlaying,
      icon: Icons.favorite_rounded,
      titleBuilder: _artDoubleTitle,
      descriptionBuilder: _artDoubleDesc,
    ),
    PulsrGestureEntry(
      id: 'artwork_swipe',
      surface: GestureSurface.nowPlaying,
      icon: Icons.compare_arrows_rounded,
      titleBuilder: _artSwipeTitle,
      descriptionBuilder: _artSwipeDesc,
    ),
    PulsrGestureEntry(
      id: 'now_playing_dismiss',
      surface: GestureSurface.nowPlaying,
      icon: Icons.keyboard_arrow_down_rounded,
      titleBuilder: _dismissTitle,
      descriptionBuilder: _dismissDesc,
    ),
    PulsrGestureEntry(
      id: 'platter_scrub',
      surface: GestureSurface.platter,
      icon: Icons.album_rounded,
      titleBuilder: _platterScrubTitle,
      descriptionBuilder: _platterScrubDesc,
    ),
    PulsrGestureEntry(
      id: 'rpm_speed_shortcut',
      surface: GestureSurface.platter,
      icon: Icons.speed_rounded,
      titleBuilder: _rpmBadgeTitle,
      descriptionBuilder: _rpmBadgeDesc,
    ),
    PulsrGestureEntry(
      id: 'waveform_pinch',
      surface: GestureSurface.waveform,
      icon: Icons.pinch_rounded,
      titleBuilder: _waveformPinchTitle,
      descriptionBuilder: _waveformPinchDesc,
    ),
    PulsrGestureEntry(
      id: 'lyrics_offset',
      surface: GestureSurface.lyrics,
      icon: Icons.sync_rounded,
      titleBuilder: _lyricsOffsetTitle,
      descriptionBuilder: _lyricsOffsetDesc,
    ),
  ];

  static List<PulsrGestureEntry> forSurface(GestureSurface surface) =>
      entries.where((e) => e.surface == surface).toList(growable: false);
}
