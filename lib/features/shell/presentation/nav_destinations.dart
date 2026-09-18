// lib/features/shell/presentation/nav_destinations.dart
//
// Single source of truth for the app's primary navigation destinations.
// The bottom dock and the landscape sidebar both consume this list so their
// order, labels and icons can never drift apart.
import 'package:flutter/material.dart';

import '../../../core/utils/l10n_extensions.dart';

class PulsrDestination {
  final int index;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const PulsrDestination({
    required this.index,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// The primary destinations, in dock order.
///
/// Settings is a primary destination again so it is always reachable from the
/// phone dock and the tablet rail; it is also still available from the Home
/// header gear.
List<PulsrDestination> pulsrDestinations(BuildContext context) => [
      PulsrDestination(
        index: 0,
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: context.l10n.navHome,
      ),
      PulsrDestination(
        index: 1,
        icon: Icons.library_music_outlined,
        activeIcon: Icons.library_music_rounded,
        label: context.l10n.navLibrary,
      ),
      PulsrDestination(
        index: 2,
        icon: Icons.search_rounded,
        activeIcon: Icons.search_rounded,
        label: context.l10n.navSearch,
      ),
      PulsrDestination(
        index: 3,
        icon: Icons.queue_music_outlined,
        activeIcon: Icons.queue_music_rounded,
        label: context.l10n.navPlaylists,
      ),
      PulsrDestination(
        index: 4,
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
        label: context.l10n.navSettings,
      ),
    ];

/// Settings' fixed shell branch index.
const int settingsDestinationIndex = 4;
