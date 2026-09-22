import 'package:flutter/widgets.dart';
import '../../../settings/cubit/settings_state.dart';
import 'card_player_theme.dart';
import 'cassette_player_theme.dart';
import 'circle_player_theme.dart';
import 'classic_player_theme.dart';
import 'lyrics_player_theme.dart';
import 'minimal_player_theme.dart';
import 'player_theme.dart';
import 'vinyl_player_theme.dart';
import 'waveform_player_theme.dart';

typedef PlayerThemeBuilder = Widget Function(PlayerThemeProps props);

/// Registry that decouples [PlayerThemeMode] from concrete theme implementations (I-09).
class ThemeRegistry {
  ThemeRegistry._();

  static final Map<PlayerThemeMode, PlayerThemeBuilder> _builders = {
    PlayerThemeMode.classic: (props) => ClassicPlayerTheme(props: props),
    PlayerThemeMode.card: (props) => CardPlayerTheme(props: props),
    PlayerThemeMode.circle: (props) => CirclePlayerTheme(props: props),
    PlayerThemeMode.minimal: (props) => MinimalPlayerTheme(props: props),
    PlayerThemeMode.vinyl: (props) => VinylPlayerTheme(props: props),
    PlayerThemeMode.cassette: (props) => CassettePlayerTheme(props: props),
    PlayerThemeMode.waveform: (props) => WaveformPlayerTheme(props: props),
    PlayerThemeMode.lyricsFocus: (props) => LyricsPlayerTheme(props: props),
  };

  /// Builds the widget corresponding to the given [mode] and [props].
  static Widget build(PlayerThemeMode mode, PlayerThemeProps props) {
    final builder = _builders[mode];
    if (builder != null) {
      return builder(props);
    }
    return ClassicPlayerTheme(props: props);
  }

  /// Allows registering custom or mock theme builders (e.g. for testing).
  @visibleForTesting
  static void register(PlayerThemeMode mode, PlayerThemeBuilder builder) {
    _builders[mode] = builder;
  }
}
