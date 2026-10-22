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
  final Widget? body;
  final Widget? sliverBody;
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
    this.body,
    this.sliverBody,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.landscapeSplit = true,
    this.onRefresh,
    this.leftPaneFlex = 4.5,
    this.rightPaneFlex = 5.5,
  });

  @override
  Widget build(BuildContext context) {
    assert(body != null || sliverBody != null,
        'DetailScaffold requires either body or sliverBody');
    final p = context.palette;
    final isLandscape = PulsrBreakpoint.isLandscape(context);
    final isTablet = Adaptive.isTablet(context);
    final shouldSplit = landscapeSplit &&
        (isLandscape || (isTablet && context.screenWidth >= 800));

    final effectiveLeading = leading ?? const PulsrBackButton();
    final effectiveTitle =
        title ?? (titleText != null ? Text(titleText!) : null);

    Widget content;

    if (shouldSplit) {
      final hinge = context.foldableHinge;
      Widget rightPane = sliverBody != null
          ? CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                      bottom: PulsrLayoutMetrics.scrollBottom(context)),
                  sliver: sliverBody,
                ),
              ],
            )
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              padding: EdgeInsets.only(
                  bottom: PulsrLayoutMetrics.scrollBottom(context)),
              child: body,
            );

      if (onRefresh != null) {
        rightPane = RefreshIndicator(
          color: p.accent,
          backgroundColor: p.surfaceContainer,
          onRefresh: onRefresh!,
          child: rightPane,
        );
      }

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
                    padding: EdgeInsetsDirectional.all(AppSpacing.md),
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
            child: rightPane,
          ),
        ],
      );
    } else {
      // Portrait / single column stacked
      Widget scrollableContent = sliverBody != null
          ? CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(child: hero),
                SliverPadding(
                  padding: EdgeInsets.only(
                      bottom: PulsrLayoutMetrics.scrollBottom(context)),
                  sliver: sliverBody,
                ),
              ],
            )
          : ListView(
              padding: EdgeInsets.only(
                  bottom: PulsrLayoutMetrics.scrollBottom(context)),
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              children: [
                hero,
                body!,
              ],
            );

      if (onRefresh != null) {
        scrollableContent = RefreshIndicator(
          color: p.accent,
          backgroundColor: p.surfaceContainer,
          onRefresh: onRefresh!,
          child: scrollableContent,
        );
      }

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
                child: scrollableContent,
              ),
            ],
          ),
        ),
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
