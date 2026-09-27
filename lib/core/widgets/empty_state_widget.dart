// lib/core/widgets/empty_state_widget.dart
import 'package:flutter/material.dart';
import 'pulsr_empty_state.dart';

export 'pulsr_empty_state.dart';

/// Legacy alias for [PulsrEmptyState], ensuring unified empty state rendering
/// without duplicating widget trees.
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? primaryActionLabel;
  final IconData? primaryActionIcon;
  final VoidCallback? onPrimaryAction;
  final bool isPrimaryLoading;
  final String? secondaryActionLabel;
  final IconData? secondaryActionIcon;
  final VoidCallback? onSecondaryAction;
  final Color? iconColor;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.primaryActionLabel,
    this.primaryActionIcon,
    this.onPrimaryAction,
    this.isPrimaryLoading = false,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.onSecondaryAction,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return PulsrEmptyState(
      icon: icon,
      title: title,
      subtitle: subtitle,
      primaryActionLabel: primaryActionLabel,
      primaryActionIcon: primaryActionIcon,
      onPrimaryAction: onPrimaryAction,
      isPrimaryLoading: isPrimaryLoading,
      secondaryActionLabel: secondaryActionLabel,
      secondaryActionIcon: secondaryActionIcon,
      onSecondaryAction: onSecondaryAction,
      iconColor: iconColor,
    );
  }
}
