part of '../settings_screen.dart';

const _categoryIds = [
  'sound',
  'look',
  'library',
  'network',
  'privacy',
  'about',
];

/// Normal-mode footer counts surfaced by [StudioBridgeFooter].
const Map<String, int> _studioControlCounts = {
  'sound': 18,
  'look': 4,
  'library': 5,
  'network': 5,
};

mixin SettingsCategoryMetadata on State<SettingsScreen> {
  late final List<_Category> _categories;

  List<_SettingsCategoryItem> _getCategories(
    BuildContext context, {
    bool pro = true,
    SettingsState? state,
  }) {
    final dev = state?.currentOutputDevice;
    final soundSubtitle = dev != null
        ? '${dev.deviceName} • ${(dev.sampleRate / 1000).toStringAsFixed(dev.sampleRate % 1000 == 0 ? 0 : 1)} kHz / ${dev.bitDepth}-bit${dev.isBitPerfectActive ? " • Bit-Perfect" : ""}'
        : context.l10n.settingsCategoryAudioSubtitle;

    return <_SettingsCategoryItem>[
      _SettingsCategoryItem(
        id: 'sound',
        title: context.l10n.settingsSectionSoundPlayback,
        subtitle: soundSubtitle,
        icon: Icons.graphic_eq_rounded,
        tintColor: AppColors.catAudio,
      ),
      _SettingsCategoryItem(
        id: 'look',
        title: context.l10n.settingsSectionAppearanceGestures,
        subtitle: context.l10n.settingsCategoryAppearanceSubtitle,
        icon: Icons.palette_outlined,
        tintColor: AppColors.catAppearance,
      ),
      _SettingsCategoryItem(
        id: 'library',
        title: context.l10n.libraryAndScanning,
        subtitle: context.l10n.settingsCategoryLibrarySubtitle,
        icon: Icons.library_music_outlined,
        tintColor: AppColors.catLibrary,
      ),
      _SettingsCategoryItem(
        id: 'network',
        title: AppConfig.ytmEnabled
            ? context.l10n.youtubeMusicAndOnline
            : context.l10n.networkAndProxy,
        subtitle: context.l10n.settingsCategoryOnlineSubtitle,
        icon: Icons.cloud_outlined,
        tintColor: AppColors.catOnline,
      ),
      _SettingsCategoryItem(
        id: 'privacy',
        title: context.l10n.privacyAndData,
        subtitle: context.l10n.settingsCategoryPrivacySubtitle,
        icon: Icons.shield_outlined,
        tintColor: AppColors.catPrivacy,
      ),
      _SettingsCategoryItem(
        id: 'about',
        title: context.l10n.about,
        subtitle:
            context.l10n.settingsCategoryAboutSubtitle(AppConfig.appVersion),
        icon: Icons.info_outline_rounded,
        tintColor: AppColors.catAbout,
      ),
    ];
  }

  void _assignCategoryTitles(BuildContext context) {
    for (final id in _categoryIds) {
      final c = _catById(id);
      switch (id) {
        case 'sound':
          c.title = context.l10n.settingsSectionSoundPlayback;
          break;
        case 'look':
          c.title = context.l10n.settingsSectionAppearanceGestures;
          break;
        case 'library':
          c.title = context.l10n.libraryAndScanning;
          break;
        case 'network':
          c.title = AppConfig.ytmEnabled
              ? context.l10n.youtubeMusicAndOnline
              : context.l10n.networkAndProxy;
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
        'sound' => Icons.graphic_eq_rounded,
        'look' => Icons.palette_outlined,
        'library' => Icons.library_music_outlined,
        'network' => Icons.cloud_outlined,
        'privacy' => Icons.shield_outlined,
        'about' => Icons.info_outline_rounded,
        _ => Icons.circle_outlined,
      };
}
