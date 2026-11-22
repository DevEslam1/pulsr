part of '../audio_quality_sheet.dart';

class _AudioQualityTabbedScaffold extends StatefulWidget {
  final bool isProfessional;
  final Color activeColor;
  final Widget signalPathHeader;
  final List<Widget> nowPlayingChildren;
  final List<Widget> outputChildren;
  final List<Widget> diagnosticsChildren;

  const _AudioQualityTabbedScaffold({
    required this.isProfessional,
    required this.activeColor,
    required this.signalPathHeader,
    required this.nowPlayingChildren,
    required this.outputChildren,
    required this.diagnosticsChildren,
  });

  @override
  State<_AudioQualityTabbedScaffold> createState() =>
      _AudioQualityTabbedScaffoldState();
}

class _AudioQualityTabbedScaffoldState
    extends State<_AudioQualityTabbedScaffold> {
  int _selectedTab = 0;
  bool _showDiagnostics = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadShowDiagnostics());
  }

  Future<void> _loadShowDiagnostics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(PrefsKeys.audioQualityShowDiagnostics);
      if (!mounted || saved == null) return;
      if (saved != _showDiagnostics) {
        setState(() => _showDiagnostics = saved);
      }
    } catch (_) {}
  }

  Future<void> _setShowDiagnostics(bool value) async {
    PulsrHaptics.selectionClick();
    setState(() {
      _showDiagnostics = value;
      if (value) {
        _selectedTab = 2;
      } else if (_selectedTab >= 2) {
        _selectedTab = 1;
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.audioQualityShowDiagnostics, value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final surfacePalette = context.playerSurfacePalette;
    final size = MediaQuery.sizeOf(context);
    final isWide = (Adaptive.isTabletLandscape(context) ||
            PulsrSheetMetrics.shouldPresentAsDialog(context)) &&
        size.width > PulsrLayoutMetrics.splitViewBreakpoint;
    final diagnosticsVisible = widget.isProfessional || _showDiagnostics;
    final maxTab = diagnosticsVisible ? 2 : 1;
    final activeTab = _selectedTab.clamp(0, maxTab);

    final segments = <PulsrSegment>[
      PulsrSegment(
        label: context.l10n.nowPlaying,
        icon: Icons.graphic_eq_rounded,
      ),
      PulsrSegment(
        label: context.l10n.audioQualityTabOutput,
        icon: Icons.speaker_group_rounded,
      ),
      if (diagnosticsVisible)
        PulsrSegment(
          label: context.l10n.audioQualityTabDiagnostics,
          icon: Icons.analytics_outlined,
        ),
    ];

    final activeChildren = switch (activeTab) {
      0 => widget.nowPlayingChildren,
      1 => widget.outputChildren,
      _ => widget.diagnosticsChildren,
    };

    final doneForeground = widget.activeColor.computeLuminance() > 0.5
        ? p.surface
        : surfacePalette.highContrastInk;

    final Widget tabContent;
    if (isWide && activeTab != 2) {
      tabContent = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.nowPlayingChildren,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: p.hairline,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.outputChildren,
              ),
            ),
          ],
        ),
      );
    } else {
      tabContent = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: activeChildren,
      );
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide
              ? PulsrLayoutMetrics.detailDialogMaxWidth
              : Adaptive.sheetConstraints(context).maxWidth,
          maxHeight: size.height * 0.90,
        ),
        child: Material(
          color: p.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.s20,
                    AppSpacing.s14,
                    AppSpacing.s20,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle Bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: p.hairline,
                            borderRadius: AppRadii.r2All,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // Live visual Signal Path Header
                      widget.signalPathHeader,
                      const SizedBox(height: AppSpacing.sm),
                      PulsrSegmentedControl(
                        selectedIndex: activeTab,
                        onChanged: (idx) {
                          PulsrHaptics.selectionClick();
                          setState(() => _selectedTab = idx);
                        },
                        segments: segments,
                      ),
                      if (!widget.isProfessional) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Material(
                          color: p.surfaceContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadii.r12All,
                            side: BorderSide(color: p.hairline),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SwitchListTile.adaptive(
                            minTileHeight: AppSpacing.minTouchTarget,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                            ),
                            secondary: Icon(
                              Icons.science_outlined,
                              size: 18,
                              color: _showDiagnostics
                                  ? widget.activeColor
                                  : p.textSecondary,
                            ),
                            title: Text(
                              context.l10n.audioQualityShowDiagnostics,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              context.l10n.audioQualityDiagnosticsProHint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: AppFontSize.caption,
                              ),
                            ),
                            value: _showDiagnostics,
                            onChanged: _setShowDiagnostics,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.s20,
                      AppSpacing.xs,
                      AppSpacing.s20,
                      AppSpacing.md,
                    ),
                    child: AnimatedSwitcher(
                      duration: context.motion(PulsrMotion.state),
                      switchInCurve: context.motionCurve(Curves.easeOutCubic),
                      switchOutCurve: context.motionCurve(Curves.easeInCubic),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(isWide && activeTab != 2
                            ? 'wide_specs_output'
                            : activeTab),
                        child: tabContent,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.s20,
                    AppSpacing.xs,
                    AppSpacing.s20,
                    AppSpacing.lg,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.activeColor,
                        foregroundColor: doneForeground,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.r14All,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        context.l10n.applyDone,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: AppFontSize.body,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
