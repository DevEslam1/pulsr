part of '../audio_quality_sheet.dart';

/// Collapsible route-specific drawer used in the Output tab of
/// [AudioQualitySheet] to separate Bluetooth, USB DAC, and Internal routes.
class AudioRouteDrawer extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String statusPill;
  final Color accentColor;
  final bool isActiveRoute;
  final bool initiallyExpanded;
  final Widget child;

  const AudioRouteDrawer({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.statusPill,
    required this.accentColor,
    required this.isActiveRoute,
    required this.initiallyExpanded,
    required this.child,
  });

  @override
  State<AudioRouteDrawer> createState() => _AudioRouteDrawerState();
}

class _AudioRouteDrawerState extends State<AudioRouteDrawer> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant AudioRouteDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActiveRoute && widget.isActiveRoute) {
      _expanded = true;
    }
  }

  void _toggle() {
    PulsrHaptics.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final animate = PulsrMotion.shouldAnimate(context);
    final duration = animate ? context.motionMs(200) : Duration.zero;
    final curve = PulsrMotion.resolveCurve(context, PulsrMotion.enter);

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(
          color: widget.isActiveRoute
              ? widget.accentColor.withValues(alpha: 0.45)
              : p.hairline,
          width: widget.isActiveRoute ? 1.3 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: '${widget.title}, ${widget.statusPill}',
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: _toggle,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s14,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: BoxDecoration(
                            color: widget.accentColor.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.icon,
                            size: 18,
                            color: widget.accentColor,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: AppFontSize.bodySmall,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                widget.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.caption,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.s2,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isActiveRoute
                                ? widget.accentColor.withValues(alpha: 0.18)
                                : p.surface,
                            borderRadius: AppRadii.r6All,
                            border: Border.all(
                              color: widget.isActiveRoute
                                  ? widget.accentColor.withValues(alpha: 0.45)
                                  : p.hairline,
                            ),
                          ),
                          child: Text(
                            widget.statusPill,
                            style: TextStyle(
                              color: widget.isActiveRoute
                                  ? widget.accentColor
                                  : p.textSecondary,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0.0,
                          duration: duration,
                          curve: curve,
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 20,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!animate)
            if (_expanded)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.s14,
                  0,
                  AppSpacing.s14,
                  AppSpacing.s14,
                ),
                child: widget.child,
              )
            else
              const SizedBox.shrink()
          else
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.s14,
                  0,
                  AppSpacing.s14,
                  AppSpacing.s14,
                ),
                child: widget.child,
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: duration,
              sizeCurve: curve,
            ),
        ],
      ),
    );
  }
}
