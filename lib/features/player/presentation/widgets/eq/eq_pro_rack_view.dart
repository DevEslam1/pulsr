part of '../equalizer_sheet.dart';

/// Professional-mode (`ExperienceMode.professional`) Studio Rack with 4 focused
/// sub-views:
/// 0. Parametric / Graphic EQ
/// 1. AutoEQ & ViPER DDC
/// 2. Spatial & HRTF
/// 3. Dynamics & Saturation
extension _EqProRackView on _EqualizerSheetState {
  List<Tab> _buildProRackTabs(BuildContext context) {
    return [
      Tab(text: context.l10n.equalizer),
      Tab(text: '${context.l10n.autoEqLabel} & DDC'),
      Tab(text: context.l10n.spatialAudio),
      Tab(text: context.l10n.studioDynamics),
    ];
  }

  Widget _buildProRackWorkspace(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p, {
    EdgeInsetsGeometry tabBarPadding =
        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
  }) {
    return Column(
      key: const ValueKey('eq_pro_rack_view'),
      children: [
        Padding(
          padding: tabBarPadding,
          child: PulsrPillTabBar(
            controller: _tabController,
            isScrollable: true,
            scrollEdgeFade: true,
            tabs: _buildProRackTabs(context),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildEqualizerTab(context, cubit, state, p),
              _buildAutoEqViperTab(context, cubit, state, p),
              _buildSpatialHrtfTab(context, cubit, state, p),
              _buildDynamicsSaturationTab(context, cubit, state, p),
            ],
          ),
        ),
      ],
    );
  }
}
