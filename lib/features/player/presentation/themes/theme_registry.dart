import 'package:flutter/widgets.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_state.dart';
import 'card_player_theme.dart';
import 'clean_player_theme.dart';
import 'cassette_player_theme.dart';
import 'cd_player_theme.dart';
import 'lyrics_player_theme.dart';
import 'milkdrop_player_theme.dart';
import 'player_theme.dart';
import 'player_theme_scaffold.dart' show PlayerThemePreviewScope;
import 'vinyl_player_theme.dart';
import 'waveform_player_theme.dart';

export 'player_theme_scaffold.dart' show PlayerThemePreviewScope;

typedef PlayerThemeBuilder = Widget Function(PlayerThemeProps props);

/// Registry that decouples [PlayerThemeMode] from concrete theme implementations (I-09).
class ThemeRegistry {
  ThemeRegistry._();

  static final Map<PlayerThemeMode, PlayerThemeBuilder> _defaultBuilders = {
    PlayerThemeMode.clean: (props) => CleanPlayerTheme(props: props),
    PlayerThemeMode.card: (props) => CardPlayerTheme(props: props),
    PlayerThemeMode.vinyl: (props) => VinylPlayerTheme(props: props),
    PlayerThemeMode.cd: (props) => CdPlayerTheme(props: props),
    PlayerThemeMode.cassette: (props) => CassettePlayerTheme(props: props),
    PlayerThemeMode.waveform: (props) => WaveformPlayerTheme(props: props),
    PlayerThemeMode.lyricsFocus: (props) => LyricsPlayerTheme(props: props),
    PlayerThemeMode.milkdrop: (props) => MilkdropPlayerTheme(props: props),
  };

  static final Map<PlayerThemeMode, PlayerThemeBuilder> _builders =
      Map.from(_defaultBuilders);

  /// Returns `true` when [context] is rendered inside a [ThemeRegistry.preview]
  /// surface with `isPreview: true`.
  static bool isPreviewOf(BuildContext context) =>
      PlayerThemePreviewScope.of(context);

  /// Builds the widget corresponding to the given [mode] and [props].
  static Widget build(PlayerThemeMode mode, PlayerThemeProps props) {
    final themedProps = props.heroTag == nowPlayingArtHeroTag(mode)
        ? props
        : props.copyWith(heroTag: nowPlayingArtHeroTag(mode));
    final builder = _builders[mode];
    if (builder != null) {
      return builder(themedProps);
    }
    return CleanPlayerTheme(props: themedProps);
  }

  /// Strips transient banners, radio recommendation cards, lyrics/queue
  /// overlays, and active transport animations from [props] so preview
  /// thumbnails stay clean and never overflow inside scaled pickers.
  static PlayerThemeProps _sanitizePreviewProps(
    PlayerThemeMode mode,
    PlayerThemeProps props,
  ) {
    final song = props.state.currentSong;
    final sanitizedSong = song != null && song.source == SongSource.radio
        ? song.copyWith(source: SongSource.local)
        : song;
    final sanitizedState = props.state.copyWith(
      playback: props.state.playback.copyWith(
        currentSong: sanitizedSong,
        isPlaying: false,
        isBuffering: false,
        bookmarkPosition: null,
        error: null,
        abLoopEnabled: false,
        abPointA: null,
        abPointB: null,
        sleepTimerRemaining: null,
        sleepTimerRemainingTracks: null,
      ),
      lyricsSlice: props.state.lyricsSlice.copyWith(
        isLyricsVisible: false,
        isQueueVisible: false,
        isLoadingLyrics: false,
      ),
    );
    return props.copyWith(
      state: sanitizedState,
      heroTag: 'now_playing_preview_${mode.name}_${identityHashCode(props)}',
    );
  }

  /// Renders a theme at scaled proportion for use in theme picker grids and previews.
  ///
  /// [canvasSize] is the logical viewport the theme is laid out against before
  /// the whole canvas is scaled into the slot. When [isPreview] is `true`
  /// (the default), transient banners, radio recommendation cards, lyrics/queue
  /// overlays, Hero transitions, device insets, and OS text scaling are
  /// suppressed inside the thumbnail so all 8 themes fit cleanly with zero
  /// [FittedBox] overflow across Light, Dark, and AMOLED modes.
  static Widget preview(
    PlayerThemeMode mode,
    PlayerThemeProps props, {
    double scale = 0.4,
    Size canvasSize = const Size(360, 640),
    bool isPreview = true,
  }) {
    final effectiveProps =
        isPreview ? _sanitizePreviewProps(mode, props) : props;
    final builtTheme = build(mode, effectiveProps);

    return IgnorePointer(
      child: SizedBox(
        width: canvasSize.width * scale,
        height: canvasSize.height * scale,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: canvasSize.width,
            height: canvasSize.height,
            child: isPreview
                ? PlayerThemePreviewHost(
                    canvasSize: canvasSize,
                    child: builtTheme,
                  )
                : builtTheme,
          ),
        ),
      ),
    );
  }

  /// Allows registering custom or mock theme builders (e.g. for testing).
  @visibleForTesting
  static void register(PlayerThemeMode mode, PlayerThemeBuilder builder) {
    _builders[mode] = builder;
  }

  /// Restores default theme builders after testing overrides.
  @visibleForTesting
  static void reset() {
    _builders.clear();
    _builders.addAll(_defaultBuilders);
  }
}

/// Normalizes [MediaQuery], disables Hero tag collisions, and establishes
/// [PlayerThemePreviewScope] for scaled theme preview thumbnails.
class PlayerThemePreviewHost extends StatelessWidget {
  final Size canvasSize;
  final Widget child;

  const PlayerThemePreviewHost({
    super.key,
    required this.canvasSize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final parentMq = MediaQuery.maybeOf(context);
    final previewMq = (parentMq ?? const MediaQueryData()).copyWith(
      size: canvasSize,
      padding: EdgeInsets.zero,
      viewPadding: EdgeInsets.zero,
      viewInsets: EdgeInsets.zero,
      textScaler: TextScaler.noScaling,
      disableAnimations: true,
    );

    return PlayerThemePreviewScope(
      isPreview: true,
      child: HeroMode(
        enabled: false,
        child: MediaQuery(
          data: previewMq,
          child: ClipRect(child: child),
        ),
      ),
    );
  }
}
