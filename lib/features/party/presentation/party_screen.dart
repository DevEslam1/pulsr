import 'package:material_ui/material_ui.dart';

import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'party_sheet.dart';

/// Full-screen home for Pulsr Party.
///
/// The feature used to exist only as a bottom sheet reachable from three
/// player/song surfaces, which made the app's flagship social feature
/// undiscoverable and impossible to deep-link. This screen gives it a stable
/// route (`/party`); the body is the existing [PartySheet] so there is one
/// implementation of the state machine, not two.
class PartyScreen extends StatelessWidget {
  final String? initialCode;
  final String? initialServerUrl;

  const PartyScreen({
    super.key,
    this.initialCode,
    this.initialServerUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.bg,
      // The body carries its own title row; the app bar exists for the back
      // affordance and desktop Escape handling.
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: Semantics(
          container: true,
          label: context.l10n.partyListenTogether,
          child: PartySheet(
            initialCode: initialCode,
            initialServerUrl: initialServerUrl,
          ),
        ),
      ),
    );
  }
}
