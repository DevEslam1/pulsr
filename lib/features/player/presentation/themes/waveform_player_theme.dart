// lib/features/player/presentation/themes/waveform_player_theme.dart
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import '../../../../core/performance/gpu_budget.dart';
import '../../../../core/services/waveform_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/audio_quality_info.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/song_options_sheet.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/player_gesture_scope.dart';
import '../widgets/player_volume_bar.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';

part 'painters/waveform_stage.dart';
part 'parts/waveform_player_theme_build.dart';

/// Studio Waveform Player Theme (Audiophile Oscilloscope):
/// Full-screen precision mastering console featuring a compact corner artwork
/// thumbnail with left-aligned metadata, a tappable monospace audio telemetry
/// readout strip (`FLAC · 24-BIT / 96.0 kHz · USB DAC`), a tall interactive
/// seekable oscilloscope waveform centerpiece replacing any thin progress bar,
/// minimal studio transport controls, and a focused EQ/Lyrics/Queue/Tools bar.
class WaveformPlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const WaveformPlayerTheme({super.key, required this.props});

  @override
  State<WaveformPlayerTheme> createState() => _WaveformPlayerThemeState();
}

class _WaveformPlayerThemeState extends State<WaveformPlayerTheme> {
  @override
  Widget build(BuildContext context) => _buildBody(context);
}
