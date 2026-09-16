import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../theme/aura_theme.dart';

/// A unified back button widget that safely navigates to the previous route,
/// falling back to the Home page ('/') if no routes can be popped.
class PulsrBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  const PulsrBackButton({
    super.key,
    this.onPressed,
    this.color,
    this.size = 22.0,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: Icon(
        Icons.arrow_back_rounded,
        color: color ?? p.textPrimary,
        size: size,
      ),
      onPressed: () {
        HapticFeedback.lightImpact();
        if (onPressed != null) {
          onPressed!();
        } else if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
    );
  }
}

