// lib/features/player/presentation/widgets/equalizer_sheet.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../data/audio/headphone_profiles_repository.dart';
import '../../../../domain/models/audio_effects_config.dart';
import '../../../../domain/models/eq_preset.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

class EqualizerSheet extends StatefulWidget {
  const EqualizerSheet({super.key});

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final HeadphoneProfilesRepository _headphoneRepo = HeadphoneProfilesRepository();

  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isLoadingProfiles = true;

  static const List<String> _bandLabels = ['32', '64', '125', '250', '500', '1K', '2K', '4K', '8K', '16K'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHeadphoneProfiles();
  }

  Future<void> _loadHeadphoneProfiles() async {
    await _headphoneRepo.loadProfiles();
    if (mounted) {
      setState(() {
        _isLoadingProfiles = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (!Platform.isAndroid) {
      return Material(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Icon(Icons.equalizer_rounded, color: p.textTertiary, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Hardware Effects Unavailable',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hardware AudioFX, Equalizer, Virtualizer and DynamicsProcessing are supported on Android devices.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();

        return Material(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: Column(
              children: [
                // Top Handle
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Header Title + Global EQ Toggle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.graphic_eq_rounded, color: p.accent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Audio Engine & Effects',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.textPrimary),
                            ),
                            Text(
                              state.isEqEnabled
                                  ? (state.selectedHeadphoneProfile != null
                                      ? 'Tuned for ${state.selectedHeadphoneProfile!.name}'
                                      : 'Preset: ${state.eqPreset.name}')
                                  : 'Audio effects bypassed',
                              style: TextStyle(fontSize: 11, color: p.textTertiary, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: state.isEqEnabled,
                        activeTrackColor: p.accent,
                        activeThumbColor: p.onAccent,
                        onChanged: (val) => cubit.setEqualizerEnabled(val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Tabs Navigation
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: p.hairline),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      tabAlignment: TabAlignment.fill,
                      indicator: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(19),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: p.onAccent,
                      unselectedLabelColor: p.textSecondary,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Equalizer'),
                        Tab(text: 'AutoEq Presets'),
                        Tab(text: 'Spatial & Dynamics'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildEqualizerTab(context, cubit, state, p),
                      _buildAutoEqTab(context, cubit, state, p),
                      _buildSpatialDynamicsTab(context, cubit, state, p),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 1. Equalizer Tab
  Widget _buildEqualizerTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    final preset = state.eqPreset;
    final isEnabled = state.isEqEnabled;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Presets Carousel
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: EqPreset.defaultPresets.length,
              itemBuilder: (context, index) {
                final presetItem = EqPreset.defaultPresets[index];
                final isSelected =
                    state.selectedHeadphoneProfile == null && preset.name == presetItem.name;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(presetItem.name),
                    selected: isSelected,
                    selectedColor: p.accent.withValues(alpha: 0.22),
                    backgroundColor: p.surfaceContainer,
                    side: BorderSide(
                      color: isSelected ? p.accent.withValues(alpha: 0.5) : p.hairline,
                    ),
                    labelStyle: TextStyle(
                      color: isSelected ? p.accent : p.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    onSelected: (_) {
                      if (!state.isEqEnabled) cubit.setEqualizerEnabled(true);
                      cubit.applyPreset(presetItem);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Active Profile Banner if AutoEq is selected
          if (state.selectedHeadphoneProfile != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.headphones_rounded, color: p.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AutoEq: ${state.selectedHeadphoneProfile!.name}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.accent,
                          ),
                        ),
                        Text(
                          '${state.selectedHeadphoneProfile!.brand} • ${state.selectedHeadphoneProfile!.category}',
                          style: TextStyle(fontSize: 10, color: p.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => cubit.applyPreset(EqPreset.defaultPresets.first),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                    child: Text('Reset', style: TextStyle(color: p.textSecondary, fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 10-Band Equalizer Vertical Sliders
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_bandLabels.length, (index) {
                final gain = index < preset.gains.length ? preset.gains[index] : 0.0;
                return Expanded(
                  child: _VerticalEqSlider(
                    value: gain,
                    label: _bandLabels[index],
                    isEnabled: isEnabled,
                    accentColor: p.accent,
                    trackColor: p.hairline,
                    surfaceColor: p.surface,
                    textColor: p.textPrimary,
                    onInteraction: () {
                      if (!state.isEqEnabled) {
                        cubit.setEqualizerEnabled(true);
                      }
                    },
                    onChanged: (val) {
                      if (!state.isEqEnabled) {
                        cubit.setEqualizerEnabled(true);
                      }
                      cubit.setBandGain(index, val);
                    },
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),

          // Bass Boost Slider
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.speaker_group_rounded, color: p.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bass Enhancer',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.textPrimary),
                      ),
                      Text(
                        '${(preset.bassBoost * 100).round()}% punch',
                        style: TextStyle(fontSize: 11, color: p.textTertiary),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: p.accent,
                      inactiveTrackColor: p.surface,
                      thumbColor: p.accent,
                    ),
                    child: Slider(
                      value: preset.bassBoost.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) {
                        if (!state.isEqEnabled) cubit.setEqualizerEnabled(true);
                        cubit.setBassBoost(val);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Volume Boost Slider (LoudnessEnhancer)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (state.volumeBoost > 0.6 ? p.error : p.accent).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.volume_up_rounded,
                        color: state.volumeBoost > 0.6 ? p.error : p.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Volume Boost',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.textPrimary),
                          ),
                          Text(
                            state.volumeBoost > 0
                                ? '+${(state.volumeBoost * 10).toStringAsFixed(1)} dB hardware gain'
                                : 'Hardware gain bypassed',
                            style: TextStyle(fontSize: 11, color: p.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (state.volumeBoost > 0.6
                                ? p.error
                                : (state.volumeBoost > 0 ? p.accent : p.surface))
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: state.volumeBoost > 0.6
                              ? p.error.withValues(alpha: 0.4)
                              : (state.volumeBoost > 0 ? p.accent.withValues(alpha: 0.3) : p.hairline),
                        ),
                      ),
                      child: Text(
                        state.volumeBoost > 0 ? '+${(state.volumeBoost * 10).toStringAsFixed(1)} dB' : 'Off',
                        style: TextStyle(
                          color: state.volumeBoost > 0.6
                              ? p.error
                              : (state.volumeBoost > 0 ? p.accent : p.textSecondary),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: state.volumeBoost > 0.6 ? p.error : p.accent,
                    inactiveTrackColor: p.surface,
                    thumbColor: state.volumeBoost > 0.6 ? p.error : p.accent,
                  ),
                  child: Slider(
                    value: state.volumeBoost.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) {
                      if (!state.isEqEnabled) cubit.setEqualizerEnabled(true);
                      cubit.setVolumeBoost(val);
                    },
                  ),
                ),
                  if (state.volumeBoost > 0.6)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 4),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: p.error, size: 13),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'High boost may cause audio distortion or hearing fatigue.',
                              style: TextStyle(color: p.error, fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),

          // Dolby Atmos / Spatial Audio Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.spatial_tracking_rounded, color: p.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Dolby Atmos / Spatial Audio',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.textPrimary),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (state.isSpatializerSupported ? p.accent : p.textTertiary).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              state.isSpatializerSupported ? 'Atmos' : 'Emulated',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: state.isSpatializerSupported ? p.accent : p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        state.isSpatializerSupported
                            ? 'Hardware spatial audio decoder active'
                            : 'Virtualizer 3D acoustic field expansion',
                        style: TextStyle(fontSize: 11, color: p.textTertiary),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: state.isSpatializerEnabled,
                  activeTrackColor: p.accent,
                  activeThumbColor: p.onAccent,
                  onChanged: (val) => cubit.setSpatializerEnabled(val),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 2. AutoEq Headphone Presets Tab
  Widget _buildAutoEqTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    if (_isLoadingProfiles) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }

    final categories = _headphoneRepo.getCategories();
    final filteredProfiles = _headphoneRepo.search(_searchQuery, category: _selectedCategory);

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.hairline),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              style: TextStyle(fontSize: 13, color: p.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search headphones (e.g. AirPods, Sony, Moondrop)...',
                hintStyle: TextStyle(fontSize: 12, color: p.textTertiary),
                prefixIcon: Icon(Icons.search_rounded, color: p.textTertiary, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, color: p.textTertiary, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),

        // Category Filter Chips
        SizedBox(
          height: 34,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: p.accent.withValues(alpha: 0.2),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(
                    color: isSelected ? p.accent.withValues(alpha: 0.4) : p.hairline,
                  ),
                  labelStyle: TextStyle(
                    color: isSelected ? p.accent : p.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedCategory = cat;
                    });
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // Active Profile Banner (if applied)
        if (state.selectedHeadphoneProfile != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: p.accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Applied Tuning Profile',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.accent),
                        ),
                        Text(
                          state.selectedHeadphoneProfile!.name,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => cubit.applyHeadphoneProfile(null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Text(
                        'Reset to Flat',
                        style: TextStyle(color: p.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Profiles List
        Expanded(
          child: filteredProfiles.isEmpty
              ? Center(
                  child: Text(
                    'No headphone profiles found.',
                    style: TextStyle(color: p.textTertiary, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filteredProfiles.length,
                  itemBuilder: (context, index) {
                    final profile = filteredProfiles[index];
                    final isApplied = state.selectedHeadphoneProfile?.id == profile.id;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            if (isApplied) {
                              await cubit.applyHeadphoneProfile(null);
                            } else {
                              if (!state.isEqEnabled) {
                                await cubit.setEqualizerEnabled(true);
                              }
                              await cubit.applyHeadphoneProfile(profile);
                            }
                          },
                          borderRadius: AppRadii.cardRadius,
                          child: Ink(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isApplied
                                  ? p.accent.withValues(alpha: 0.14)
                                  : p.surfaceContainer,
                              borderRadius: AppRadii.cardRadius,
                              border: Border.all(
                                color: isApplied
                                    ? p.accent
                                    : p.hairline,
                                width: isApplied ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: (isApplied ? p.accent : p.textTertiary)
                                        .withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    profile.category == 'Over-Ear'
                                        ? Icons.headset_rounded
                                        : Icons.headphones_rounded,
                                    color: isApplied ? p.accent : p.textSecondary,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        profile.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: isApplied ? p.accent : p.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${profile.brand} • ${profile.category}',
                                        style: TextStyle(fontSize: 11, color: p.textTertiary),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isApplied)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: p.accent,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: p.accent.withValues(alpha: 0.35),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_rounded, color: p.onAccent, size: 13),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Active',
                                          style: TextStyle(
                                            color: p.onAccent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: p.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: p.hairline),
                                    ),
                                    child: Text(
                                      'Apply',
                                      style: TextStyle(
                                        color: p.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // 3. Spatial & Dynamics Tab
  Widget _buildSpatialDynamicsTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Support Detection Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: state.isSpatializerSupported
                  ? p.accent.withValues(alpha: 0.12)
                  : p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(
                color: state.isSpatializerSupported
                    ? p.accent.withValues(alpha: 0.4)
                    : p.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  state.isSpatializerSupported
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  color: state.isSpatializerSupported ? p.accent : p.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.isSpatializerSupported
                            ? 'Hardware Spatializer Detected'
                            : 'Emulated 3D Widening Mode',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: state.isSpatializerSupported ? p.accent : p.textPrimary,
                        ),
                      ),
                      Text(
                        state.isSpatializerSupported
                            ? 'Dolby Atmos & system spatial decoding available'
                            : 'Stereo field widening active via hardware virtualizer',
                        style: TextStyle(fontSize: 10, color: p.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Dolby Atmos / Spatial Audio
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.spatial_tracking_rounded, color: p.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Dolby Atmos / Spatial Audio',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.textPrimary),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (state.isSpatializerSupported ? p.accent : p.textTertiary).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              state.isSpatializerSupported ? 'Atmos' : 'Emulated',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: state.isSpatializerSupported ? p.accent : p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        state.isSpatializerSupported
                            ? 'Hardware spatial audio decoder'
                            : 'Virtualizer 3D acoustic field expansion',
                        style: TextStyle(fontSize: 11, color: p.textTertiary),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: state.isSpatializerEnabled,
                  activeTrackColor: p.accent,
                  activeThumbColor: p.onAccent,
                  onChanged: (val) => cubit.setSpatializerEnabled(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stereo Soundstage Expansion (Virtualizer)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.surround_sound_rounded, color: p.accent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Soundstage Widening',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.textPrimary),
                            ),
                            Text(
                              'Virtualizer stereo field expansion',
                              style: TextStyle(fontSize: 11, color: p.textTertiary),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: state.isVirtualizerEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged: (val) => cubit.setVirtualizerEnabled(val),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Soundstage visual animation / dispersion indicator
                Opacity(
                  opacity: state.isVirtualizerEnabled ? 1.0 : 0.35,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Width', style: TextStyle(fontSize: 12, color: p.textSecondary, fontWeight: FontWeight.w600)),
                          Text(
                            '${(state.virtualizerStrength * 100).round()}%',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.accent),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          activeTrackColor: p.accent,
                          inactiveTrackColor: p.surface,
                          thumbColor: p.accent,
                        ),
                        child: Slider(
                          value: state.virtualizerStrength.clamp(0.0, 1.0),
                          min: 0.0,
                          max: 1.0,
                          onChanged: state.isVirtualizerEnabled
                              ? (val) => cubit.setVirtualizerStrength(val)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Studio Dynamics (DynamicsProcessing)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.compress_rounded, color: p.accent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Studio Dynamics & Limiter',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.textPrimary),
                            ),
                            Text(
                              'Multiband compression engine',
                              style: TextStyle(fontSize: 11, color: p.textTertiary),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: state.isDynamicsEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged: (val) {
                        cubit.setDynamicsPreset(
                          val
                              ? (state.dynamicsPreset == DynamicsPreset.off
                                  ? DynamicsPreset.studioPunch
                                  : state.dynamicsPreset)
                              : DynamicsPreset.off,
                          enabled: val,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Dynamics Preset Cards Grid
                Opacity(
                  opacity: state.isDynamicsEnabled ? 1.0 : 0.35,
                  child: Column(
                    children: DynamicsPreset.values.where((d) => d != DynamicsPreset.off).map((preset) {
                      final isSelected =
                          state.isDynamicsEnabled && state.dynamicsPreset == preset;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: state.isDynamicsEnabled
                              ? () => cubit.setDynamicsPreset(preset, enabled: true)
                              : null,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? p.accent.withValues(alpha: 0.15)
                                  : p.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? p.accent.withValues(alpha: 0.5)
                                    : p.hairline,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  color: isSelected ? p.accent : p.textTertiary,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        preset.label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected ? p.accent : p.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        preset.description,
                                        style: TextStyle(fontSize: 10, color: p.textTertiary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalEqSlider extends StatefulWidget {
  final double value;
  final bool isEnabled;
  final String label;
  final Color accentColor;
  final Color trackColor;
  final Color surfaceColor;
  final Color textColor;
  final ValueChanged<double> onChanged;
  final VoidCallback? onInteraction;

  static const double min = -15.0;
  static const double max = 15.0;

  const _VerticalEqSlider({
    required this.value,
    required this.isEnabled,
    required this.label,
    required this.accentColor,
    required this.trackColor,
    required this.surfaceColor,
    required this.textColor,
    required this.onChanged,
    this.onInteraction,
  });

  @override
  State<_VerticalEqSlider> createState() => _VerticalEqSliderState();
}

class _VerticalEqSliderState extends State<_VerticalEqSlider> {
  bool _isDragging = false;
  double? _dragGain;

  void _handlePointer(double localY, double totalHeight) {
    widget.onInteraction?.call();
    const topMargin = 12.0;
    const bottomMargin = 12.0;
    final trackHeight = totalHeight - topMargin - bottomMargin;
    if (trackHeight <= 0) return;
    final clampedY = (localY - topMargin).clamp(0.0, trackHeight);
    final fraction = 1.0 - (clampedY / trackHeight);
    final newGain = _VerticalEqSlider.min + fraction * (_VerticalEqSlider.max - _VerticalEqSlider.min);
    final roundedGain = double.parse(newGain.toStringAsFixed(1));
    setState(() {
      _dragGain = roundedGain;
    });
    widget.onChanged(roundedGain);
  }

  @override
  Widget build(BuildContext context) {
    final gain = (_isDragging && _dragGain != null ? _dragGain! : widget.value)
        .clamp(_VerticalEqSlider.min, _VerticalEqSlider.max);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Value Pill
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (gain.abs() > 0.1 ? widget.accentColor : widget.trackColor).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
              style: TextStyle(
                fontSize: 10,
                color: gain.abs() > 0.1 ? widget.accentColor : widget.textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Vertical Slider Track
        SizedBox(
          height: 140,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              const topMargin = 12.0;
              const bottomMargin = 12.0;
              final trackHeight = height - topMargin - bottomMargin;
              final fraction = (gain - _VerticalEqSlider.min) / (_VerticalEqSlider.max - _VerticalEqSlider.min);
              final thumbY = topMargin + (1.0 - fraction) * trackHeight;
              final centerY = topMargin + trackHeight / 2;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (details) {
                  setState(() => _isDragging = true);
                  _handlePointer(details.localPosition.dy, height);
                },
                onVerticalDragUpdate: (details) {
                  _handlePointer(details.localPosition.dy, height);
                },
                onVerticalDragEnd: (_) {
                  setState(() {
                    _isDragging = false;
                    _dragGain = null;
                  });
                },
                onVerticalDragCancel: () {
                  setState(() {
                    _isDragging = false;
                    _dragGain = null;
                  });
                },
                onTapDown: (details) {
                  _handlePointer(details.localPosition.dy, height);
                },
                child: CustomPaint(
                  size: Size(constraints.maxWidth, height),
                  painter: _VerticalSliderPainter(
                    fraction: fraction,
                    thumbY: thumbY,
                    centerY: centerY,
                    topMargin: topMargin,
                    bottomMargin: bottomMargin,
                    isDragging: _isDragging,
                    isEnabled: widget.isEnabled,
                    accentColor: widget.accentColor,
                    trackColor: widget.trackColor,
                    surfaceColor: widget.surfaceColor,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // Frequency Label
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: widget.textColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _VerticalSliderPainter extends CustomPainter {
  final double fraction;
  final double thumbY;
  final double centerY;
  final double topMargin;
  final double bottomMargin;
  final bool isDragging;
  final bool isEnabled;
  final Color accentColor;
  final Color trackColor;
  final Color surfaceColor;

  _VerticalSliderPainter({
    required this.fraction,
    required this.thumbY,
    required this.centerY,
    required this.topMargin,
    required this.bottomMargin,
    required this.isDragging,
    required this.isEnabled,
    required this.accentColor,
    required this.trackColor,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final trackTop = topMargin;
    final trackBottom = size.height - bottomMargin;

    // Background track (Pill)
    final bgPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.35)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    canvas.drawLine(
      Offset(centerX, trackTop),
      Offset(centerX, trackBottom),
      bgPaint,
    );

    // Center 0 dB notch tick
    final notchPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.8)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0;

    canvas.drawLine(
      Offset(centerX - 6, centerY),
      Offset(centerX + 6, centerY),
      notchPaint,
    );

    // Active fill from center (0dB) to thumbY
    final activePaint = Paint()
      ..color = isEnabled ? accentColor : trackColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX, thumbY),
      activePaint,
    );

    // Thumb Glow / Halo when dragging
    if (isDragging && isEnabled) {
      final haloPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, thumbY), 16.0, haloPaint);
    }

    // Thumb Outer Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawCircle(Offset(centerX, thumbY + 1), isDragging ? 9.0 : 8.0, shadowPaint);

    // Thumb Main Circle
    final thumbPaint = Paint()
      ..color = isEnabled ? accentColor : trackColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, thumbY), isDragging ? 9.0 : 8.0, thumbPaint);

    // Thumb Inner Core
    final corePaint = Paint()
      ..color = isEnabled ? Colors.white : surfaceColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, thumbY), isDragging ? 3.5 : 3.0, corePaint);
  }

  @override
  bool shouldRepaint(covariant _VerticalSliderPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.thumbY != thumbY ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.isEnabled != isEnabled ||
        oldDelegate.accentColor != accentColor;
  }
}
