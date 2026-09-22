import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (onPop != null) {
          onPop!();
          return;
        }
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop();
        } else {
          router.go('/');
        }
      },
      child: child,
    );
  }
}
