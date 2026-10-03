part of '../settings_screen.dart';

class _SettingsCategoryItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color tintColor;

  const _SettingsCategoryItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tintColor,
  });
}

class _Category {
  final String id;
  final IconData icon;
  String title = '';
  final GlobalKey key;

  _Category(this.id, this.icon) : key = GlobalKey();
}

class _SearchItem {
  final String categoryId;
  final String category;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> keywords;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Professional-only setting; hidden from Normal-mode search.
  final bool pro;

  _SearchItem({
    this.categoryId = '',
    required this.category,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.keywords,
    this.trailing,
    this.onTap,
    this.pro = false,
  });
}

class _SuperSectionCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _SuperSectionCard({
    required this.title,
    required this.icon,
    required this.isExpanded,
    required this.onToggle,
    required this.children,
  });

  @override
  State<_SuperSectionCard> createState() => _SuperSectionCardState();
}

class _SuperSectionCardState extends State<_SuperSectionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PulsrMotion.standard,
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _SuperSectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isExpanded = widget.isExpanded;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: '${widget.title}, ${isExpanded ? "expanded" : "collapsed"}',
            child: PulsrPressable(
              pressedScale: 0.985,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onToggle();
              },
              child: AnimatedContainer(
                duration: context.motionMs(200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: isExpanded
                      ? p.surfaceContainer
                      : p.surfaceContainer.withValues(alpha: 0.6),
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(
                    color: isExpanded
                        ? p.accent.withValues(alpha: 0.45)
                        : p.hairline,
                    width: isExpanded ? 1.4 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isExpanded
                            ? p.accent.withValues(alpha: 0.16)
                            : p.accentContainer.withValues(alpha: 0.4),
                        borderRadius: AppRadii.r10All,
                      ),
                      child: Icon(widget.icon, color: p.accent, size: 18),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.title.toUpperCase(),
                        style: TextStyle(
                          color: isExpanded ? p.textPrimary : p.textSecondary,
                          fontSize: AppFontSize.callout,
                          fontWeight: FontWeight.w800,
                          letterSpacing: AppTracking.heading,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.0 : -0.25,
                      duration: context.motionMs(220),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isExpanded
                              ? p.accent.withValues(alpha: 0.12)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: isExpanded ? p.accent : p.textTertiary,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              if (_controller.value == 0.0 && !widget.isExpanded) {
                return const SizedBox(width: double.infinity);
              }
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _animation.value,
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
