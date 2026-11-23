// lib/features/ytm_search/presentation/ytm_search_screen.dart
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../search/presentation/search_screen.dart';

/// Thin compatibility wrapper for the legacy `/ytm-search` deep-link route.
///
/// Unifies online YouTube Music search directly into [SearchScreen] with
/// `initialScope: SearchScope.online`, `autofocus: true`, and a back button for
/// pushed root-navigator routes (`context.push('/ytm-search')`).
///
/// New callers (such as Wave 3's `HomeScreen`) can navigate directly to
/// `SearchScreen.routeLocation(scope: SearchScope.online, autofocus: true)`
/// to stay inside the shell Search tab, or keep using `/ytm-search` with zero
/// regressions.
class YtmSearchScreen extends StatelessWidget {
  final String? initialQuery;
  final bool autofocus;

  const YtmSearchScreen({
    super.key,
    this.initialQuery,
    this.autofocus = true,
  });

  @override
  Widget build(BuildContext context) {
    return PulsrPagePopScope(
      child: SearchScreen(
        initialQuery: initialQuery,
        initialScope: SearchScope.online,
        autofocus: autofocus,
        showBackButton: true,
        enableOnlineOverride: true,
      ),
    );
  }
}
