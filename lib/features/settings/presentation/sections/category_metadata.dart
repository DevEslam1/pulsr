part of '../settings_screen.dart';

const _categoryIds = [
  'audio',
  'playback',
  'appearance',
  'gestures',
  'profiles',
  'automation',
  'library',
  'online',
  'storage',
  'privacy',
  'about',
];

/// Normal-mode footer counts surfaced by [StudioBridgeFooter].
const Map<String, int> _studioControlCounts = {
  'audio': 12,
  'playback': 6,
  'appearance': 4,
  'library': 3,
  'online': 5,
  'storage': 2,
};

mixin SettingsCategoryMetadata on State<SettingsScreen> {
  late final List<_Category> _categories;

  List<_SettingsCategoryItem> _getCategories(BuildContext context,
      {bool pro = true}) {
    final categories = <_SettingsCategoryItem>[
      _SettingsCategoryItem(
        id: 'audio',
        title: context.l10n.audioAndSound,
        subtitle: context.l10n.settingsCategoryAudioSubtitle,
        icon: Icons.equalizer_rounded,
        tintColor: AppColors.catAudio,
      ),
      _SettingsCategoryItem(
        id: 'playback',
        title: context.l10n.playback,
        subtitle: context.l10n.settingsCategoryPlaybackSubtitle,
        icon: Icons.play_circle_outline_rounded,
        tintColor: AppColors.catPlayback,
      ),
      _SettingsCategoryItem(
        id: 'appearance',
        title: context.l10n.settingsCategoryAppearance,
        subtitle: context.l10n.settingsCategoryAppearanceSubtitle,
        icon: Icons.palette_outlined,
        tintColor: AppColors.catAppearance,
      ),
      _SettingsCategoryItem(
        id: 'gestures',
        title: context.l10n.gestures,
        subtitle: context.l10n.settingsCategoryGesturesSubtitle,
        icon: Icons.swipe_rounded,
        tintColor: AppColors.catGestures,
      ),
      _SettingsCategoryItem(
        id: 'profiles',
        title: context.l10n.settingsCategoryProfiles,
        subtitle: context.l10n.settingsCategoryProfilesSubtitle,
        icon: Icons.devices_other_rounded,
        tintColor: AppColors.catProfiles,
      ),
      _SettingsCategoryItem(
        id: 'library',
        title: context.l10n.navLibrary,
        subtitle: context.l10n.settingsCategoryLibrarySubtitle,
        icon: Icons.library_music_outlined,
        tintColor: AppColors.catLibrary,
      ),
      _SettingsCategoryItem(
        id: 'online',
        title: context.l10n.settingsCategoryOnline,
        subtitle: context.l10n.settingsCategoryOnlineSubtitle,
        icon: Icons.cloud_outlined,
        tintColor: AppColors.catOnline,
      ),
      _SettingsCategoryItem(
        id: 'storage',
        title: context.l10n.storageAndCache,
        subtitle: context.l10n.settingsCategoryStorageSubtitle,
        icon: Icons.storage_rounded,
        tintColor: AppColors.catStorage,
      ),
      _SettingsCategoryItem(
        id: 'privacy',
        title: context.l10n.settingsCategoryPrivacy,
        subtitle: context.l10n.settingsCategoryPrivacySubtitle,
        icon: Icons.shield_outlined,
        tintColor: AppColors.catPrivacy,
      ),
      _SettingsCategoryItem(
        id: 'about',
        title: context.l10n.settingsCategoryAbout,
        subtitle:
            context.l10n.settingsCategoryAboutSubtitle(AppConfig.appVersion),
        icon: Icons.info_outline_rounded,
        tintColor: AppColors.catAbout,
      ),
    ];
    // Normal mode hides the advanced "Profiles & Rules" surface (device-profile
    // mappings and automation triggers). Smart Audio lives in Audio & Sound.
    if (!pro) {
      categories.removeWhere((c) => c.id == 'profiles');
    }
    return categories;
  }

  void _assignCategoryTitles(BuildContext context) {
    for (final id in _categoryIds) {
      final c = _catById(id);
      switch (id) {
        case 'audio':
          c.title = context.l10n.audioAndSound;
          break;
        case 'playback':
          c.title = context.l10n.playback;
          break;
        case 'appearance':
          c.title = context.l10n.themeAndAppearance;
          break;
        case 'gestures':
          c.title = context.l10n.gestures;
          break;
        case 'profiles':
          c.title = context.l10n.deviceProfilesTitle;
          break;
        case 'automation':
          c.title = context.l10n.settingsAutomationTitle;
          break;
        case 'library':
          c.title = context.l10n.libraryAndScanning;
          break;
        case 'online':
          c.title = AppConfig.ytmEnabled
              ? context.l10n.youtubeMusicAndOnline
              : context.l10n.networkAndProxy;
          break;
        case 'storage':
          c.title = context.l10n.storageAndCache;
          break;
        case 'privacy':
          c.title = context.l10n.privacyAndData;
          break;
        case 'about':
          c.title = context.l10n.about;
          break;
        default:
          c.title = id;
          break;
      }
    }
  }

  _Category _catById(String id) => _categories.firstWhere((c) => c.id == id,
      orElse: () => _categories.first);

  Widget _catSection(BuildContext context, String id, Widget child) =>
      KeyedSubtree(key: _catById(id).key, child: child);

  IconData _iconFor(String id) => switch (id) {
        'audio' => Icons.equalizer_rounded,
        'playback' => Icons.play_circle_outline_rounded,
        'appearance' => Icons.palette_outlined,
        'gestures' => Icons.swipe_rounded,
        'profiles' => Icons.phone_android_rounded,
        'automation' => Icons.bolt_rounded,
        'library' => Icons.library_music_outlined,
        'online' => Icons.cloud_outlined,
        'storage' => Icons.storage_rounded,
        'privacy' => Icons.privacy_tip_outlined,
        'about' => Icons.info_outline_rounded,
        _ => Icons.circle_outlined,
      };
}
