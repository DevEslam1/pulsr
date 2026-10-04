part of '../settings_screen.dart';

mixin SettingsScreenController on State<SettingsScreen> {
  // Requires: provided by the composing class (same library).
  String get _selectedCategoryId;
  set _selectedCategoryId(String value);

  // Requires: provided by the composing class (same library).
  ScrollController get _scrollController;

  // Requires: provided by the composing class (same library).
  TextEditingController get _searchController;

  // Requires: provided by the composing class (same library).
  String get _searchQuery;
  set _searchQuery(String value);

  Timer? _searchDebounce;

  static String _sessionCategoryId = 'all';

  @visibleForTesting
  static void resetSessionCategory() => _sessionCategoryId = 'all';

  /// Maps legacy category IDs from earlier versions onto the 6 consolidated destination IDs.
  static String normalizeCategoryId(String id) {
    return switch (id) {
      'audio' || 'playback' || 'profiles' || 'automation' => 'sound',
      'appearance' || 'gestures' => 'look',
      'storage' || 'library' => 'library',
      'online' => 'network',
      'privacy' => 'privacy',
      'about' => 'about',
      _ => id,
    };
  }

  void _selectCategory(String catId) {
    final normalized = normalizeCategoryId(catId);
    if (_selectedCategoryId == normalized) return;
    _sessionCategoryId = normalized;
    setState(() => _selectedCategoryId = normalized);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: context.motionMs(280),
        curve: context.motionCurve(Curves.easeOutCubic),
      );
    }
  }

  void _restoreLastCategory() {
    // Normalise session category if stale
    _sessionCategoryId = normalizeCategoryId(_sessionCategoryId);
    if (_selectedCategoryId != _sessionCategoryId &&
        (_categoryIds.contains(_sessionCategoryId) || _sessionCategoryId == 'all')) {
      setState(() => _selectedCategoryId = _sessionCategoryId);
    }
    // Read and map any legacy disk-persisted category from prior versions
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString('settings_last_selected_category');
      if (saved != null) {
        final mapped = normalizeCategoryId(saved);
        if (_categoryIds.contains(mapped) || mapped == 'all') {
          if (mounted && _selectedCategoryId != mapped) {
            _sessionCategoryId = mapped;
            setState(() => _selectedCategoryId = mapped);
          }
        }
      }
      prefs.remove('settings_last_selected_category');
    }).catchError((_) {});
  }

  void _bindSearchListener() {
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text.isEmpty && _searchQuery.isNotEmpty) {
        _searchDebounce?.cancel();
        if (mounted) setState(() => _searchQuery = '');
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: context.motionMs(240),
            curve: context.motionCurve(Curves.easeOutCubic),
          );
        }
        return;
      }
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        final q = text.trim().toLowerCase();
        if (q != _searchQuery) {
          setState(() => _searchQuery = q);
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0.0,
              duration: context.motionMs(240),
              curve: context.motionCurve(Curves.easeOutCubic),
            );
          }
        }
      });
    });
  }

  /// Rebuilds the settings shell only when state this tree actually renders
  /// changes. Transient fields owned by other surfaces are ignored so an async
  /// probe or validation error can't force a full rebuild of the whole screen:
  /// - `errorMessage` is surfaced by the app-level snackbar listener (main.dart).
  /// - `isTestingAllProxies` drives the separate proxy screen's `BlocConsumer`.
  /// - `systemEffectsBundles` is not rendered here (only `systemEffectsStatus`).
  static bool _settingsBuildWhen(
      SettingsState previous, SettingsState current) {
    SettingsState scrub(SettingsState s) => s.copyWith(
          errorMessage: null,
          isTestingAllProxies: false,
          systemEffectsBundles: const <String>[],
        );
    return scrub(previous) != scrub(current);
  }
}
