// Playlists screen's reused card components, extracted so the screen file keeps
// shrinking (ratchet 01-4). Part of playlists_screen.dart, so the private
// class names and imports stay shared.
part of 'playlists_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Reused local components
// ─────────────────────────────────────────────────────────────────────────────

class _PlaylistHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  const _PlaylistHeroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.r22All,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: AppRadii.r22All,
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.35),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.specularAt(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: AppFontSize.title,
                      letterSpacing: AppTracking.title,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.specularAt(0.8),
                      fontSize: AppFontSize.label,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: colors.first,
                size: 26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final bool muted;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final List<PopupMenuEntry<String>> Function(BuildContext)? menuItems;
  final void Function(String)? onMenuSelected;

  const _PlaylistCard({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.muted = false,
    this.isSelected = false,
    this.onLongPress,
    this.menuItems,
    this.onMenuSelected,
  });

  void _openContextMenu(BuildContext context, Offset globalPosition) {
    final items = menuItems?.call(context);
    if (items == null || items.isEmpty) return;
    HapticFeedback.selectionClick();
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: items,
    ).then((selected) {
      if (selected != null) onMenuSelected?.call(selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = Semantics(
      button: true,
      selected: isSelected,
      label: name,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.r20All,
        child: AnimatedContainer(
          duration: context.motion(PulsrMotion.state),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: AppRadii.r20All,
            border: Border.all(
              color: isSelected ? p.accent : p.hairline,
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: p.glow.withValues(alpha: 0.32),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: muted
                                ? p.accent.withValues(alpha: 0.12)
                                : Colors.white.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            icon,
                            color: muted ? p.accent : Colors.white,
                            size: 30,
                          ),
                        ),
                      ),

                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.s14,
                  AppSpacing.s10,
                  AppSpacing.xs,
                  AppSpacing.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected ? p.accent : p.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: AppFontSize.body,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (menuItems != null)
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 18,
                          color: p.textTertiary,
                        ),
                        onSelected: onMenuSelected,
                        itemBuilder: menuItems!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (menuItems != null) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (d) => _openContextMenu(context, d.globalPosition),
        child: card,
      );
    }
    if (onLongPress != null) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: onLongPress,
        child: card,
      );
    }
    return card;
  }
}

class DashedBorderCard extends StatelessWidget {
  final Widget child;
  final Color color;
  const DashedBorderCard({super.key, required this.child, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: AppRadii.r18All,
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.4),
        color: color.withValues(alpha: 0.06),
      ),
      child: child,
    );
  }
}
