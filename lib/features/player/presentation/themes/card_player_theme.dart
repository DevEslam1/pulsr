// lib/features/player/presentation/themes/card_player_theme.dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_blur.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/song_options_sheet.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/canvas_backdrop.dart';
import '../widgets/player_gesture_scope.dart';
import '../widgets/player_volume_bar.dart';
import '../widgets/radio_now_playing_recommendations.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart' show PlayerThemeMetrics;

part 'parts/card_player_theme_build.dart';

/// Card Glass Overlay — Spatial Frosted Sheet Now Playing theme.
///
/// Decoupled from `PlayerThemeScaffold` via [PlayerSurfaceShell]:
/// 1. Full-screen live blurred artwork canvas filling 100% of the viewport
///    (strictly gated by [AppBlur.canBlur] + [AppBlur.clampSigma], with a rich
///    blurred-feel tinted gradient fallback when blur is disabled).
/// 2. Interactive swipeable stacked album card deck powered by
///    [resolveQueueNeighbors] showing peeking previous/next track cards behind
///    the active center card (`resolveCustomRadius(context, 24)` +
///    `resolveCustomGlow(context)`), with smooth horizontal drag & spring
///    snap-back.
/// 3. Single unified frosted-glass floating control card at the bottom with a
///    crisp specular top border (`AppColors.specularAt`), housing track header,
///    `BlocSelector`-scoped glass scrubber, spatial glass transport controls
///    (no A/B clutter), and compact Lyrics / Queue / [PlayerToolsTriggerButton]
///    footer row.
class CardPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const CardPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) => _buildBody(context);
}
