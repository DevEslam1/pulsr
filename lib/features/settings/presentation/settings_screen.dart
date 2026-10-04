import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/pulsr_segmented_control.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/missing_artwork_service.dart';
import '../../../core/services/sound_feedback_service.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_pressable.dart';
import '../../../core/widgets/pulsr_search_field.dart';
import '../../../core/widgets/pulsr_slider.dart';
import '../../../core/widgets/pulsr_switch.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../../shell/presentation/widgets/dock_style_picker_sheet.dart';
import '../../shell/presentation/widgets/dock_style_controller.dart';
import '../cubit/settings_accessibility_ext.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';
import '../../../core/utils/platform_capabilities.dart';
import '../../player/presentation/widgets/equalizer_sheet.dart';
import '../../sheets/sleep_timer_sheet.dart';
import 'widgets/audio_setup_wizard.dart';
import 'widgets/audio_sound_section.dart';
import 'widgets/automation_rules_sheet.dart';
import 'widgets/backup_section.dart';
import 'widgets/cast_section.dart';
import 'widgets/device_profiles_section.dart';
import 'widgets/download_settings_tiles.dart';
import 'widgets/experience_mode_section.dart';
import 'widgets/smart_audio_section.dart';
import 'widgets/playback_section.dart';
import 'widgets/scrobbler_settings_modal.dart';
import 'widgets/settings_hero_card.dart';
import 'widgets/settings_picker_sheets.dart';
import 'widgets/settings_section.dart';
import 'widgets/storage_cache_section.dart';
import 'widgets/studio_bridge_footer.dart';
import 'widgets/theme_schedule_row.dart';
import 'widgets/ytm_account_disconnect_dialog.dart';
import 'widgets/settings_tiles.dart';
import '../../../core/widgets/highlighted_text.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

part 'sections/settings_screen_models.dart';
part 'sections/category_metadata.dart';
part 'sections/settings_section_primitives.dart';
part 'sections/settings_header_section.dart';
part 'sections/category_filter_bar_section.dart';
part 'sections/appearance_section.dart';
part 'sections/gestures_section.dart';
part 'sections/library_section.dart';
part 'sections/online_section.dart';
part 'sections/privacy_backup_section.dart';
part 'sections/search_results_section.dart';
part 'sections/settings_category_widgets_section.dart';
part 'sections/tablet_layout_section.dart';
part 'sections/phone_layout_section.dart';
part 'sections/settings_screen_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen>
    with
        SettingsCategoryMetadata,
        SettingsSectionPrimitives,
        SettingsScreenController,
        SettingsHeaderSection,
        CategoryFilterBarSection,
        SettingsAppearanceSection,
        SettingsGesturesSection,
        SettingsLibrarySection,
        SettingsOnlineSection,
        SettingsPrivacyBackupSection,
        SettingsSearchResults,
        SettingsCategoryWidgetsSection,
        TabletLayoutSection,
        PhoneLayoutSection {
  @override
  final ScrollController _scrollController = ScrollController();
  @override
  final TextEditingController _searchController = TextEditingController();

  @override
  String _selectedCategoryId = 'all';
  @override
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _categories =
        _categoryIds.map((id) => _Category(id, _iconFor(id))).toList();
    _restoreLastCategory();
    // FIX-H05: Debounce search results via Timer with immediate clear on empty
    _bindSearchListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _assignCategoryTitles(context);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      buildWhen: SettingsScreenController._settingsBuildWhen,
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();

        final isLandscapePhone =
            context.isLandscape && MediaQuery.sizeOf(context).height < 500;
        final isTabletView = !isLandscapePhone &&
            ((context.breakpoint >= PulsrBreakpoint.medium &&
                    (context.isLandscape ||
                        Adaptive.widthOf(context) >= 700)) ||
                context.isTwoPane);
        // H6/M3: A selected category can disappear when Professional mode is
        // turned off (e.g. `profiles`). Normalise the persisted selection in the
        // same frame so the master rail highlight and the detail pane can never
        // disagree, then reset the stale id so it doesn't resurface when
        // Professional mode is re-enabled.
        final categories = _getCategories(context, pro: state.isProfessional);
        var selectedCategoryId = _selectedCategoryId;
        if (selectedCategoryId != 'all' &&
            !categories.any((c) => c.id == selectedCategoryId)) {
          selectedCategoryId = categories.first.id;
          final corrected = selectedCategoryId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedCategoryId != corrected) {
              setState(() => _selectedCategoryId = corrected);
            }
          });
        }
        final effectiveCategoryId =
            (isTabletView && selectedCategoryId == 'all')
                ? 'sound'
                : selectedCategoryId;

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: isTabletView
                  ? _buildTabletLayout(
                      context, state, cubit, effectiveCategoryId)
                  : _buildPhoneLayout(context, state, cubit),
            ),
          ),
        );
      },
    );
  }
}
