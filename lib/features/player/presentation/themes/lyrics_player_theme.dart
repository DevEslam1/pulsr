// lib/features/player/presentation/themes/lyrics_player_theme.dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_blur.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/lyrics/advanced_lyrics_view.dart';
import '../widgets/player_gesture_scope.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart' show PlayerThemeMetrics;

part 'parts/lyrics_player_theme_build.dart';

/// Theme 7: Karaoke Lyrics Immersion — Lyrics-First Stage.
///
/// Decoupled from `PlayerThemeScaffold` via [PlayerSurfaceShell] with
/// `handlesLyricsInline: true` so the synced lyrics stage owns ~70% of the
/// viewport without a competing square album cover:
/// 1. Rich album-tinted ambient stage backdrop with soft spotlight aura.
/// 2. Compact top bar: dismiss chevron, 40x40 rounded art thumbnail, track
///    title/artist, favorite heart, Queue toggle, and [PlayerToolsTriggerButton].
/// 3. Synced scrolling LRC stage with magnified glowing active line, smooth
///    top/bottom [ShaderMask] fade, depth-of-field blur, and tap-to-seek, plus
///    clean loading, empty, unsynced, and Theme Picker preview states.
/// 4. Ultra-slim floating frosted translucent progress + transport pill.
class LyricsPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const LyricsPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) => _buildBody(context);
}
