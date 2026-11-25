import 'package:material_ui/material_ui.dart';

import '../motion/pulsr_motion.dart';

/// {@category DesignSystem}
/// The Pulsr route family expressed as a [PageTransitionsBuilder].
///
/// This replaces the per-route `CustomTransitionPage` that used to override
/// every `GoRoute`: because a custom `transitionsBuilder` bypasses
/// `PageTransitionsTheme`, Android 14's predictive-back preview never had a
/// chance to run. Registering this builder in [ThemeData.pageTransitionsTheme]
/// and returning [MaterialPage] from the router keeps the same tuned
/// slide + fade + parallax, while letting the framework own the route and the
/// platform own the back gesture.
class PulsrPageTransitionsBuilder extends PageTransitionsBuilder {
  const PulsrPageTransitionsBuilder();

  @override
  Duration get transitionDuration => PulsrMotion.page;

  @override
  Duration get reverseTransitionDuration => PulsrMotion.layout;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!context.motionEnabled) return child;

    // Primary entrance: slide in from the trailing edge with a fade.
    final slide = animation.drive(
      Tween<Offset>(
        begin: const Offset(0.12, 0.0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.fastEaseInToSlowEaseOut)),
    );
    final fade = animation.drive(
      Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).chain(
          CurveTween(curve: const Interval(0.0, 0.75, curve: Curves.easeOut))),
    );

    // Secondary exit: subtle Apple-style parallax recession.
    final secondarySlide = secondaryAnimation.drive(
      Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.04, 0.0),
      ).chain(CurveTween(curve: Curves.fastEaseInToSlowEaseOut)),
    );
    final secondaryFade = secondaryAnimation.drive(
      Tween<double>(
        begin: 1.0,
        end: 0.92,
      ).chain(CurveTween(curve: Curves.fastEaseInToSlowEaseOut)),
    );

    return SlideTransition(
      position: secondarySlide,
      child: FadeTransition(
        opacity: secondaryFade,
        child: SlideTransition(
          position: slide,
          child: FadeTransition(
            opacity: fade,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Now Playing as a non-opaque, fade + scale surface.
///
/// `opaque: false` is the point: the shell keeps painting behind the player, so
/// dragging it away reveals the library and mini player instead of a blank
/// stage. The surface Hero (see `hero_tags.dart`) carries the rest of the
/// continuity.
class PulsrNowPlayingPage<T> extends Page<T> {
  final Widget child;

  const PulsrNowPlayingPage({
    required this.child,
    super.key,
    super.name,
    super.restorationId,
  });

  @override
  Route<T> createRoute(BuildContext context) {
    return PageRouteBuilder<T>(
      settings: this,
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: PulsrMotion.page,
      reverseTransitionDuration: PulsrMotion.layout,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (!context.motionEnabled) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: PulsrMotion.enter,
          reverseCurve: PulsrMotion.exit,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 1.0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }
}

/// Calm cross-fade + lift used between the five shell tabs.
///
/// Tab switches are lateral, not a descent, so they intentionally do not share
/// the push/pop slide. [NoTransitionPage] would be instantly cheaper but reads
/// as a hard cut; this keeps the change legible while staying under one
/// [PulsrDurations.state] window.
class PulsrTabPageTransitionsBuilder extends PageTransitionsBuilder {
  const PulsrTabPageTransitionsBuilder();

  @override
  Duration get transitionDuration => PulsrMotion.state;

  @override
  Duration get reverseTransitionDuration => PulsrMotion.state;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!context.motionEnabled) return child;
    final fade = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    final slide = animation.drive(
      Tween<Offset>(
        begin: const Offset(0.0, 0.012),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: child,
      ),
    );
  }
}
