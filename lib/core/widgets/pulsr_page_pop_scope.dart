import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import 'pulsr_modal_tracker.dart';

/// {@category DesignSystem}
/// Wraps any screen in a predictive PopScope that ensures the physical/system
/// back button returns to the previous route, or gracefully falls back to the
/// Home page ('/') when at the root of a branch or stack.
class PulsrPagePopScope extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPop;

  const PulsrPagePopScope({
    super.key,
    required this.child,
    this.onPop,
  });

  @override
  Widget build(BuildContext context) {
    // `maybeOf` keeps the widget usable in tests and in subtrees that are not
    // under the app router; only the pop *callback* used to touch GoRouter,
    // and moving that lookup into build broke those cases.
    final router = GoRouter.maybeOf(context);
    final canPop =
        router?.canPop() ?? (Navigator.maybeOf(context)?.canPop() ?? false);
    return PopScope(
      // Reporting the real value is what lets Android 14 draw the
      // predictive-back preview. The old hard-coded `false` suppressed the
      // animation on every screen and forced the callback path.
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (PulsrModalTracker.isModalOpen.value) {
          final rootNav = rootNavigatorKey.currentState;
          if (rootNav != null && rootNav.canPop()) {
            rootNav.maybePop();
            return;
          }
        }
        if (onPop != null) {
          onPop!();
          return;
        }
        if (router != null) {
          if (router.canPop()) {
            router.pop();
          } else {
            router.go('/');
          }
        } else {
          Navigator.maybeOf(context)?.maybePop();
        }
      },
      child: child,
    );
  }
}
