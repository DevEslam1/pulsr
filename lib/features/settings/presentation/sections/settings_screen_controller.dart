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

  void _selectCategory(String catId) {
    if (_selectedCategoryId == catId) return;
    setState(() => _selectedCategoryId = catId);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: context.motionMs(280),
        curve: context.motionCurve(Curves.easeOutCubic),
      );
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('settings_last_selected_category', catId);
    }).catchError((_) {});
  }

  void _restoreLastCategory() {
    SharedPreferences.getInstance().then((prefs) {
      final savedCat = prefs.getString('settings_last_selected_category');
      if (savedCat != null && _categoryIds.contains(savedCat) && mounted) {
        setState(() => _selectedCategoryId = savedCat);
      }
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
