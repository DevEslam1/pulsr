// lib/core/constants/pulsr_icons.dart
import 'package:flutter/material.dart';

/// {@category DesignSystem}
/// Semantic iconography system for Pulsr.
///
/// Maps semantic roles to concrete Material/Cupertino icon data so icon set swaps,
/// style changes (rounded vs filled vs outlined), and design system updates
/// can be completed in a single file without modifying dozens of widgets.
abstract class PulsrIcons {
  // ── Playback Controls ────────────────────────────────────────────────────
  static const IconData play = Icons.play_arrow_rounded;
  static const IconData pause = Icons.pause_rounded;
  static const IconData stop = Icons.stop_rounded;
  static const IconData skipNext = Icons.skip_next_rounded;
  static const IconData skipPrevious = Icons.skip_previous_rounded;
  static const IconData fastForward = Icons.fast_forward_rounded;
  static const IconData fastRewind = Icons.fast_rewind_rounded;
  static const IconData shuffle = Icons.shuffle_rounded;
  static const IconData repeat = Icons.repeat_rounded;
  static const IconData repeatOne = Icons.repeat_one_rounded;
  static const IconData speed = Icons.speed_rounded;

  // ── Navigation Destinations (Active / Inactive pairs) ────────────────────
  static const IconData home = Icons.home_outlined;
  static const IconData homeFilled = Icons.home_rounded;
  static const IconData library = Icons.library_music_outlined;
  static const IconData libraryFilled = Icons.library_music_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData searchFilled = Icons.search_rounded;
  static const IconData downloads = Icons.download_outlined;
  static const IconData downloadsFilled = Icons.download_done_rounded;
  static const IconData settings = Icons.settings_outlined;
  static const IconData settingsFilled = Icons.settings_rounded;

  // ── Actions & Feedback ───────────────────────────────────────────────────
  static const IconData favorite = Icons.favorite_rounded;
  static const IconData favoriteBorder = Icons.favorite_border_rounded;
  static const IconData playlistAdd = Icons.playlist_add_rounded;
  static const IconData playlistPlay = Icons.playlist_play_rounded;
  static const IconData queue = Icons.queue_music_rounded;
  static const IconData lyrics = Icons.lyrics_rounded;
  static const IconData equalizer = Icons.equalizer_rounded;
  static const IconData share = Icons.share_rounded;
  static const IconData delete = Icons.delete_outline_rounded;
  static const IconData deleteFilled = Icons.delete_rounded;
  static const IconData edit = Icons.edit_rounded;
  static const IconData moreVert = Icons.more_vert_rounded;
  static const IconData moreHoriz = Icons.more_horiz_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData checkCircle = Icons.check_circle_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData expandMore = Icons.expand_more_rounded;
  static const IconData expandLess = Icons.expand_less_rounded;
  static const IconData chevronRight = Icons.chevron_right_rounded;
  static const IconData chevronLeft = Icons.chevron_left_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData sort = Icons.sort_rounded;
  static const IconData filter = Icons.filter_list_rounded;

  // ── Media Entities ───────────────────────────────────────────────────────
  static const IconData song = Icons.music_note_rounded;
  static const IconData album = Icons.album_rounded;
  static const IconData artist = Icons.person_rounded;
  static const IconData playlist = Icons.queue_music_rounded;
  static const IconData folder = Icons.folder_rounded;
  static const IconData genre = Icons.category_rounded;
  static const IconData year = Icons.calendar_today_rounded;

  // ── Smart Audio & Hardware ───────────────────────────────────────────────
  static const IconData headphones = Icons.headphones_rounded;
  static const IconData speaker = Icons.speaker_rounded;
  static const IconData bluetooth = Icons.bluetooth_rounded;
  static const IconData dac = Icons.album_rounded;
  static const IconData cast = Icons.cast_rounded;
  static const IconData castConnected = Icons.cast_connected_rounded;
  static const IconData tune = Icons.tune_rounded;
  static const IconData graphicEq = Icons.graphic_eq_rounded;
  static const IconData volumeUp = Icons.volume_up_rounded;
  static const IconData volumeMute = Icons.volume_mute_rounded;
  static const IconData mic = Icons.mic_rounded;

  // ── System & Status ──────────────────────────────────────────────────────
  static const IconData info = Icons.info_outline_rounded;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData error = Icons.error_outline_rounded;
  static const IconData sync = Icons.sync_rounded;
  static const IconData offline = Icons.cloud_off_rounded;
  static const IconData wifi = Icons.wifi_rounded;
  static const IconData battery = Icons.battery_charging_full_rounded;
  static const IconData security = Icons.security_rounded;
}
