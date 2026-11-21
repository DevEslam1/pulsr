// lib/features/player/presentation/widgets/mini_player/mini_player_tablet_bar.dart
import 'package:material_ui/material_ui.dart';

import '../tablet_player_bar.dart';

/// Tablet-optimized player bar variant.
class MiniPlayerTablet extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onToggleSideInspector;
  final bool isInspectorOpen;

  const MiniPlayerTablet({
    super.key,
    required this.onTap,
    this.onToggleSideInspector,
    this.isInspectorOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    return TabletPlayerBar(
      onOpenNowPlaying: onTap,
      onToggleSideInspector: onToggleSideInspector,
      isInspectorOpen: isInspectorOpen,
    );
  }
}
