// lib/features/player/presentation/themes/player_shape.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';

/// Optional live-preview override used by [CustomThemeBuilderScreen] so
/// dragging the corner radius slider or toggling ambient glow updates the
/// embedded player theme preview immediately without persisting on every frame.
class PlayerShapePreviewOverride extends InheritedWidget {
  final double? cornerRadius;
  final bool? ambientGlow;

  const PlayerShapePreviewOverride({
    super.key,
    this.cornerRadius,
    this.ambientGlow,
    required super.child,
  });

  static PlayerShapePreviewOverride? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerShapePreviewOverride>();

  @override
  bool updateShouldNotify(PlayerShapePreviewOverride oldWidget) =>
      cornerRadius != oldWidget.cornerRadius ||
      ambientGlow != oldWidget.ambientGlow;
}

/// Resolves the Custom Theme Studio corner radius.
///
/// Only when the user selected the custom colour source does their radius win;
/// preset themes keep their own hand-tuned geometry and [fallback] is returned.
double resolveCustomRadius(BuildContext context, double fallback) {
  final previewOverride =
      PlayerShapePreviewOverride.maybeOf(context)?.cornerRadius;
  if (previewOverride != null) return previewOverride;
  final shape =
      context.select<SettingsCubit, ({double radius, bool active})>((c) => (
            radius: c.state.customThemeRadius,
            active: c.state.themeColorSource == ThemeColorSource.custom,
          ));
  return shape.active ? shape.radius : fallback;
}

/// Whether the custom Ambient Glow should be applied (custom source + enabled).
bool resolveCustomGlow(BuildContext context) {
  final previewOverride =
      PlayerShapePreviewOverride.maybeOf(context)?.ambientGlow;
  if (previewOverride != null) return previewOverride;
  final glow =
      context.select<SettingsCubit, ({bool glow, bool active})>((c) => (
            glow: c.state.customThemeGlow,
            active: c.state.themeColorSource == ThemeColorSource.custom,
          ));
  return glow.active && glow.glow;
}
