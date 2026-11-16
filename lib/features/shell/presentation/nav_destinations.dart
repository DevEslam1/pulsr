// lib/features/shell/presentation/nav_destinations.dart
//
// Single source of truth for the app's primary navigation destinations.
// The bottom dock and the landscape sidebar both consume this list so their
// order, labels and icons can never drift apart.
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/l10n_extensions.dart';

@immutable
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

  /// Returns the appropriate icon for the current selection state.
  IconData iconForState({required bool isSelected}) =>
      isSelected ? activeIcon : icon;

  PulsrDestination copyWith({
    int? index,
    IconData? icon,
    IconData? activeIcon,
    String? label,
  }) {
    return PulsrDestination(
      index: index ?? this.index,
      icon: icon ?? this.icon,
      activeIcon: activeIcon ?? this.activeIcon,
      label: label ?? this.label,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PulsrDestination &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          icon == other.icon &&
          activeIcon == other.activeIcon &&
          label == other.label;

  @override
  int get hashCode => Object.hash(index, icon, activeIcon, label);
}

/// The primary destinations, in dock order.
///
/// Settings is a primary destination again so it is always reachable from the
/// phone dock and the tablet rail; it is also still available from the Home
/// header gear.
// FIX-L6: Cache navigation destinations by Locale to avoid rebuilding on every frame.
// Bounded to a few locales: a long-lived process that sees many locales (locale
// switcher, tests, system changes) must not grow this map without limit.
final Map<Locale, List<PulsrDestination>> _destinationsCache = {};
const int _maxCachedLocales = 4;

/// Number of locales currently cached (test seam for the bound).
@visibleForTesting
int get debugNavDestinationsCacheSize => _destinationsCache.length;

@visibleForTesting
void debugClearNavDestinationsCache() => _destinationsCache.clear();

@visibleForTesting
void debugSeedNavDestinationsCache(
        Locale locale, List<PulsrDestination> value) =>
    _storeInCache(locale, value);

void _storeInCache(Locale locale, List<PulsrDestination> destinations) {
  _destinationsCache.remove(locale);
  _destinationsCache[locale] = destinations;
  while (_destinationsCache.length > _maxCachedLocales) {
    _destinationsCache.remove(_destinationsCache.keys.first);
  }
}

List<PulsrDestination> pulsrDestinations(BuildContext context) {
  final locale = Localizations.localeOf(context);
  final cached = _destinationsCache.remove(locale);
  if (cached != null) {
    // Re-insert to keep the map in LRU order.
    _destinationsCache[locale] = cached;
    return cached;
  }

  final destinations = List<PulsrDestination>.unmodifiable([
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
  ]);

  _storeInCache(locale, destinations);
  return destinations;
}

/// Settings' fixed shell branch index.
const int settingsDestinationIndex = 4;
