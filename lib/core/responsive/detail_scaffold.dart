// lib/core/responsive/detail_scaffold.dart
import 'package:flutter/material.dart';
import '../constants/app_spacing.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';
import '../widgets/pulsr_back_button.dart';
import '../widgets/pulsr_page_pop_scope.dart';
import 'breakpoints.dart';
import 'pulsr_layout_metrics.dart';

/// Adaptive scaffold for Detail screens (Album, Artist, Genre, Year, Folder).
///
/// - Phone Portrait & Tablet Portrait:
///   Content is vertically stacked within [PulsrLayoutMetrics.contentConstraints].
/// - Phone Landscape & Tablet Landscape:
///   Layout splits into side-by-side panes:
///   - Left pane: Hero metadata, artwork, and primary actions.
///   - Right pane: Scrollable item/track list.
///   - Supports foldable hinge separation when present.
class DetailScaffold extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final String? titleText;
  final List<Widget>? actions;
  final Widget hero;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool landscapeSplit;
  final Future<void> Function()? onRefresh;
  final double leftPaneFlex;
  final double rightPaneFlex;

  const DetailScaffold({
    super.key,
    this.leading,
    this.title,
    this.titleText,
    this.actions,
    required this.hero,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.landscapeSplit = true,
    this.onRefresh,
    this.leftPaneFlex = 4.5,
    this.rightPaneFlex = 5.5,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isLandscape = PulsrBreakpoint.isLandscape(context);
    final isTablet = Adaptive.isTablet(context);
    final shouldSplit = landscapeSplit && (isLandscape || (isTablet && context.screenWidth >= 800));

    final effectiveLeading = leading ?? const PulsrBackButton();
    final effectiveTitle = title ?? (titleText != null ? Text(titleText!) : null);

    Widget content;

    if (shouldSplit) {
      final hinge = context.foldableHinge;
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Pane: Hero, artwork & actions
          Expanded(
            flex: (leftPaneFlex * 10).round(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppBar(
                  leading: effectiveLeading,
                  title: effectiveTitle,
                  actions: actions,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                    child: Center(child: hero),
                  ),
                ),
              ],
            ),
          ),

          // Foldable hinge or divider
          if (hinge != null)
            SizedBox(width: hinge.bounds.width)
          else
            VerticalDivider(width: 1, thickness: 1, color: p.hairline),

          // Right Pane: Content list
          Expanded(
            flex: (rightPaneFlex * 10).round(),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: AppSpacing.scrollBottom),
              child: body,
            ),
          ),
        ],
      );
    } else {
      // Portrait / single column stacked
      content = Center(
        child: ConstrainedBox(
          constraints: PulsrLayoutMetrics.contentConstraints(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBar(
                leading: effectiveLeading,
                title: effectiveTitle,
                actions: actions,
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.scrollBottom),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    hero,
                    body,
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (onRefresh != null) {
      content = RefreshIndicator(
        color: p.accent,
        backgroundColor: p.surfaceContainer,
        onRefresh: onRefresh!,
        child: content,
      );
    }

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          bottom: false,
          child: content,
        ),
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}
