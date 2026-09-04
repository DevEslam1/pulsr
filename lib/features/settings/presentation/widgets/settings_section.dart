// lib/features/settings/presentation/widgets/settings_section.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';

/// A titled, card-wrapped settings group.
///
/// Shared container used by every group on the settings screen so all
/// sections are labeled and styled consistently (small accent header label +
/// rounded card body, matching the original hand-rolled `_section` helper).
class SettingsSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 0, 10),
            child: Row(
              children: [
                Icon(icon, size: 14, color: p.accent),
                const SizedBox(width: 6),
                Text(title.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6)),
              ],
            ),
          ),
          Material(
            color: p.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: p.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}
