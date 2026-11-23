import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/services/radio_station_store.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/theme/pulsr_button_style.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../domain/models/radio_station.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import '../../../../core/utils/pulsr_haptics.dart';

part 'quran_radio_hero_painters.dart';

/// Data descriptor for a Quran radio station presented in the hero card carousel.
class QuranHeroItem {
  final RadioStation station;
  final String reciterTitleAr;
  final String reciterTitleEn;
  final String subtitleAr;
  final String subtitleEn;
  final String artworkAsset;
  final String? badgeTextAr;
  final String? badgeTextEn;

  const QuranHeroItem({
    required this.station,
    required this.reciterTitleAr,
    required this.reciterTitleEn,
    required this.subtitleAr,
    required this.subtitleEn,
    required this.artworkAsset,
    this.badgeTextAr,
    this.badgeTextEn,
  });

  String get reciterTitle => reciterTitleAr;
  String get subtitle => subtitleAr;
  String? get badgeText => badgeTextAr;

  String getReciterTitle(bool isArabic) =>
      isArabic ? reciterTitleAr : reciterTitleEn;
  String getSubtitle(bool isArabic) => isArabic ? subtitleAr : subtitleEn;
  String? getBadgeText(bool isArabic) => isArabic ? badgeTextAr : badgeTextEn;
}

/// Swipeable Quran Radio Hero Carousel — "Mihrab" edition.
///
/// Each station is presented as a luminous prayer-niche: reciter artwork framed
/// inside a pointed arch on the trailing edge, a hand-drawn eight-fold khatam
/// lattice etched across the surface, manuscript-gilt ornamentation derived
/// from the active theme accent, live transport controls, parallax artwork
/// framing, and a diamond-windowed page indicator.
class QuranRadioHeroCarousel extends StatefulWidget {
  final PlayerCubit? playerCubit;
  final double height;
  final VoidCallback? onMoreStations;
  final bool autoScroll;
  final Duration autoScrollInterval;

  const QuranRadioHeroCarousel({
    super.key,
    this.playerCubit,
    this.height = 152.0,
    this.onMoreStations,
    this.autoScroll = true,
    this.autoScrollInterval = const Duration(seconds: 12),
  });

  /// The curated list of Quran stations ordered specifically with Minshawi first.
  static List<QuranHeroItem> defaultQuranStations() {
    return [
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-minshawi',
          name: 'إذاعة الشيخ محمد صديق المنشاوي (مجود)',
          url:
              'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi_mojawwad',
          genre: 'Quran',
          artworkUrl: RadioStationStore.minshawiHomeCard,
        ),
        reciterTitleAr: 'الشيخ محمد صديق المنشاوي',
        reciterTitleEn: 'Sheikh Mohamed Siddiq El-Minshawi',
        subtitleAr: 'المصحف المجود • تلاوة خاشعة',
        subtitleEn: 'Holy Quran • Reverent Mujawwad Recitation',
        artworkAsset: RadioStationStore.minshawiHomeCard,
        badgeTextAr: 'تلاوة خاشعة',
        badgeTextEn: 'Khashia Recitation',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-khashia',
          name: 'إذاعة تلاوات خاشعة نادرة',
          url: 'https://backup.qurango.net/radio/salma',
          genre: 'Quran',
          artworkUrl: RadioStationStore.khashiaHomeCard,
        ),
        reciterTitleAr: 'إذاعة تلاوات خاشعة نادرة',
        reciterTitleEn: 'Rare Khashia Recitations Radio',
        subtitleAr: 'تلاوات خاشعة ومؤثرة • كبار القراء',
        subtitleEn: 'Rare Reverent Recitations • Master Reciters',
        artworkAsset: RadioStationStore.khashiaHomeCard,
        badgeTextAr: 'تلاوات خاشعة',
        badgeTextEn: 'Rare Recitations',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-minshawi-rare',
          name: 'إذاعة الشيخ محمد صديق المنشاوي (تلاوات نادرة)',
          url: 'https://radio.xecod.com/station/alminshawi',
          genre: 'Quran',
          artworkUrl: RadioStationStore.minshawiHomeCard,
        ),
        reciterTitleAr: 'الشيخ محمد صديق المنشاوي',
        reciterTitleEn: 'Sheikh Mohamed Siddiq El-Minshawi',
        subtitleAr: 'تلاوات نادرة ومحافل خاشعة',
        subtitleEn: 'Rare Historic Recitations & Concerts',
        artworkAsset: RadioStationStore.minshawiHomeCard,
        badgeTextAr: 'تلاوات نادرة',
        badgeTextEn: 'Historic Recitations',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-cairo',
          name: 'إذاعة القرآن الكريم المصرية - القاهرة',
          url: 'https://stream.radiojar.com/8s5u5tpdtwzuv',
          genre: 'Quran',
          artworkUrl: RadioStationStore.quranCairoHomeCard,
        ),
        reciterTitleAr: 'إذاعة القرآن الكريم - القاهرة',
        reciterTitleEn: 'Holy Quran Radio - Cairo',
        subtitleAr: 'بث مباشر من القاهرة • عبر الأثير',
        subtitleEn: 'Live from Cairo • Over the Air',
        artworkAsset: RadioStationStore.quranCairoHomeCard,
        badgeTextAr: 'بث مباشر',
        badgeTextEn: 'Live Broadcast',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-abdulbasit',
          name: 'إذاعة الشيخ عبد الباسط عبد الصمد (مجود)',
          url:
              'https://backup.qurango.net/radio/abdulbasit_abdulsamad_mojawwad',
          genre: 'Quran',
          artworkUrl: RadioStationStore.abdulBasitHomeCard,
        ),
        reciterTitleAr: 'الشيخ عبد الباسط عبد الصمد',
        reciterTitleEn: 'Sheikh Abdulbasit Abdulsamad',
        subtitleAr: 'صوت مكة • المصحف المجود',
        subtitleEn: 'Voice of Mecca • Holy Quran Mujawwad',
        artworkAsset: RadioStationStore.abdulBasitHomeCard,
        badgeTextAr: 'المصحف المجود',
        badgeTextEn: 'Mujawwad Mushaf',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-hussary',
          name: 'إذاعة الشيخ محمود خليل الحصري (مرتل)',
          url: 'https://backup.qurango.net/radio/mahmoud_khalil_alhussary',
          genre: 'Quran',
          artworkUrl: RadioStationStore.hussaryHomeCard,
        ),
        reciterTitleAr: 'الشيخ محمود خليل الحصري',
        reciterTitleEn: 'Sheikh Mahmoud Khalil Al-Hussary',
        subtitleAr: 'شيخ عموم المقارئ المصرية • المصحف المعلم',
        subtitleEn: 'Master of Reciters • Teaching Mushaf',
        artworkAsset: RadioStationStore.hussaryHomeCard,
        badgeTextAr: 'المصحف المعلم',
        badgeTextEn: 'Teacher Mushaf',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-mustafa',
          name: 'إذاعة الشيخ مصطفى إسماعيل (مجود)',
          url: 'https://backup.qurango.net/radio/mustafa_ismail',
          genre: 'Quran',
          artworkUrl: RadioStationStore.mustafaIsmailHomeCard,
        ),
        reciterTitleAr: 'الشيخ مصطفى إسماعيل',
        reciterTitleEn: 'Sheikh Mustafa Ismail',
        subtitleAr: 'قارئ الملوك والرؤساء • إعجاز التلاوة',
        subtitleEn: 'Legendary Reciter • Miraculous Recitation',
        artworkAsset: RadioStationStore.mustafaIsmailHomeCard,
        badgeTextAr: 'المصحف المجود',
        badgeTextEn: 'Mujawwad Mushaf',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-banna-mojawwad',
          name: 'إذاعة الشيخ محمود علي البنا (مجود)',
          url: 'https://backup.qurango.net/radio/mahmoud_ali__albanna_mojawwad',
          genre: 'Quran',
          artworkUrl: RadioStationStore.bannaHomeCard,
        ),
        reciterTitleAr: 'الشيخ محمود علي البنا',
        reciterTitleEn: 'Sheikh Mahmoud Ali Al-Banna',
        subtitleAr: 'المصحف المجود • صوت شجي خاشع',
        subtitleEn: 'Holy Quran Mujawwad • Melodious Voice',
        artworkAsset: RadioStationStore.bannaHomeCard,
        badgeTextAr: 'المصحف المجود',
        badgeTextEn: 'Mujawwad Mushaf',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-tablaway',
          name: 'إذاعة الشيخ محمد محمود الطبلاوي',
          url: 'https://backup.qurango.net/radio/mohammad_altablaway',
          genre: 'Quran',
          artworkUrl: RadioStationStore.tablawayHomeCard,
        ),
        reciterTitleAr: 'الشيخ محمد محمود الطبلاوي',
        reciterTitleEn: 'Sheikh Mohammad Al-Tablaway',
        subtitleAr: 'تلاوات خاشعة نادرة • نبرة مميزة',
        subtitleEn: 'Rare Recitations • Distinctive Tone',
        artworkAsset: RadioStationStore.tablawayHomeCard,
        badgeTextAr: 'تلاوات خاشعة',
        badgeTextEn: 'Khashia Recitations',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-tarteel',
          name: 'إذاعة تراتيل قصيرة متميزة',
          url: 'https://backup.qurango.net/radio/tarateel',
          genre: 'Quran',
          artworkUrl: RadioStationStore.tarteelHomeCard,
        ),
        reciterTitleAr: 'إذاعة تراتيل القرآن الكريم',
        reciterTitleEn: 'Holy Quran Short Recitations Radio',
        subtitleAr: 'تلاوات عذبة مختارة على مدار الساعة',
        subtitleEn: 'Sweet Recitations 24/7',
        artworkAsset: RadioStationStore.tarteelHomeCard,
        badgeTextAr: 'تراتيل عذبة',
        badgeTextEn: 'Sweet Tarteel',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-cairo-backup',
          name: 'إذاعة القرآن الكريم - القاهرة (بث بديل)',
          url: 'https://radio.xecod.com/station/quran-cairo',
          genre: 'Quran',
          artworkUrl: RadioStationStore.quranCairoHomeCard,
        ),
        reciterTitleAr: 'إذاعة القرآن الكريم - القاهرة',
        reciterTitleEn: 'Holy Quran Radio - Cairo',
        subtitleAr: 'بث بديل عالي الجودة',
        subtitleEn: 'High Quality Backup Stream',
        artworkAsset: RadioStationStore.quranCairoHomeCard,
        badgeTextAr: 'بث بديل',
        badgeTextEn: 'Backup Stream',
      ),
    ];
  }

  /// Builds a [QuranHeroItem] for a station loaded dynamically from [RadioStationStore].
  @visibleForTesting
  static QuranHeroItem buildMergedHeroItem(RadioStation station) {
    final isCurated = station.id.startsWith('cur-');
    final lowerId = station.id.toLowerCase();
    final lowerName = station.name.toLowerCase();
    final titleAr = RadioStationStore.localizedStationName(station, 'ar');
    final titleEn = RadioStationStore.localizedStationName(station, 'en');
    final homeCard = RadioStationStore.resolveHomeCardForStation(
      id: station.id,
      name: station.name,
      url: station.url,
    );

    late final String subtitleAr;
    late final String subtitleEn;
    late final String badgeAr;
    late final String badgeEn;

    if (!isCurated) {
      final genre = station.genre?.trim();
      subtitleAr =
          genre != null && genre.isNotEmpty ? genre : 'إذاعة القرآن الكريم';
      subtitleEn =
          genre != null && genre.isNotEmpty ? genre : 'Holy Quran Radio';
      badgeAr = 'إذاعة مخصصة';
      badgeEn = 'Custom Station';
    } else if (lowerId.contains('murattal') || lowerName.contains('مرتل')) {
      subtitleAr = 'المصحف المرتل • تلاوة خاشعة';
      subtitleEn = 'Holy Quran • Murattal Recitation';
      badgeAr = 'المصحف المرتل';
      badgeEn = 'Murattal';
    } else if (lowerId.contains('mojawwad') || lowerName.contains('مجود')) {
      subtitleAr = 'المصحف المجود • تلاوة خاشعة';
      subtitleEn = 'Holy Quran • Mujawwad Recitation';
      badgeAr = 'المصحف المجود';
      badgeEn = 'Mujawwad';
    } else if (lowerId.contains('makkah')) {
      subtitleAr = 'بث مباشر من المسجد الحرام';
      subtitleEn = 'Live from Masjid al-Haram';
      badgeAr = 'الحرم المكي';
      badgeEn = 'Mecca Live';
    } else if (lowerId.contains('sakeenah')) {
      subtitleAr = 'تلاوات هادئة للسكينة والطمأنينة';
      subtitleEn = 'Calm Recitations for Peace';
      badgeAr = 'آيات السكينة';
      badgeEn = 'Serenity';
    } else {
      subtitleAr = 'إذاعة القرآن الكريم • بث متواصل';
      subtitleEn = 'Holy Quran Radio • 24/7 Stream';
      badgeAr = 'إذاعة القرآن';
      badgeEn = 'Quran Radio';
    }

    return QuranHeroItem(
      station: station,
      reciterTitleAr: titleAr,
      reciterTitleEn: titleEn,
      subtitleAr: subtitleAr,
      subtitleEn: subtitleEn,
      artworkAsset:
          homeCard ?? station.artworkUrl ?? RadioStationStore.minshawiHomeCard,
      badgeTextAr: badgeAr,
      badgeTextEn: badgeEn,
    );
  }

  /// Orders [baseItems] with [pinnedUrls] first (preserving pinned priority)
  /// and sorts the remaining items according to [sortMode].
  @visibleForTesting
  static List<QuranHeroItem> sortAndPinItems(
    List<QuranHeroItem> baseItems, {
    required List<String> pinnedUrls,
    required QuranHeroSortMode sortMode,
    required bool isArabic,
    Map<String, int> lastPlayedByUrl = const {},
  }) {
    if (baseItems.isEmpty) return const [];
    final byUrl = <String, QuranHeroItem>{};
    final indexByUrl = <String, int>{};
    for (var i = 0; i < baseItems.length; i++) {
      final item = baseItems[i];
      byUrl[item.station.url] = item;
      indexByUrl[item.station.url] = i;
    }

    final pinnedSet = <String>{};
    final pinned = <QuranHeroItem>[];
    for (final url in pinnedUrls) {
      final match = byUrl[url];
      if (match != null && pinnedSet.add(url)) {
        pinned.add(match);
      }
    }

    final unpinned = baseItems
        .where((item) => !pinnedSet.contains(item.station.url))
        .toList();

    switch (sortMode) {
      case QuranHeroSortMode.curated:
        break;
      case QuranHeroSortMode.alphabetical:
        unpinned.sort((a, b) {
          final cmp = a
              .getReciterTitle(isArabic)
              .toLowerCase()
              .compareTo(b.getReciterTitle(isArabic).toLowerCase());
          if (cmp != 0) return cmp;
          return (indexByUrl[a.station.url] ?? 0)
              .compareTo(indexByUrl[b.station.url] ?? 0);
        });
      case QuranHeroSortMode.recentlyPlayed:
        unpinned.sort((a, b) {
          final aPlayed =
              lastPlayedByUrl[a.station.url] ?? a.station.lastPlayed ?? 0;
          final bPlayed =
              lastPlayedByUrl[b.station.url] ?? b.station.lastPlayed ?? 0;
          final cmp = bPlayed.compareTo(aPlayed);
          if (cmp != 0) return cmp;
          return (indexByUrl[a.station.url] ?? 0)
              .compareTo(indexByUrl[b.station.url] ?? 0);
        });
    }

    return [...pinned, ...unpinned];
  }

  @override
  State<QuranRadioHeroCarousel> createState() => _QuranRadioHeroCarouselState();
}

class _QuranRadioHeroCarouselState extends State<QuranRadioHeroCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;
  late List<QuranHeroItem> _baseItems;
  Map<String, int> _lastPlayedByUrl = const {};
  List<QuranHeroItem> _stations = const [];
  bool _isArabic = false;
  Timer? _autoScrollTimer;

  @visibleForTesting
  bool get isAutoScrollTimerActive => _autoScrollTimer?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    final curated = QuranRadioHeroCarousel.defaultQuranStations();
    _baseItems = curated;
    _stations = curated;
    _pageController = PageController(
      initialPage: 0,
      viewportFraction: 0.93,
    );
    RadioStationStore.heroPinnedUrls.addListener(_onOrderPrefsChanged);
    RadioStationStore.heroSortMode.addListener(_onOrderPrefsChanged);

    // Merge any custom user stations dynamically
    final store = RadioStationStore();
    store.ready.then((_) {
      if (!mounted) return;
      final lastPlayedMap = <String, int>{};
      for (final s in store.list) {
        if (s.lastPlayed != null && s.lastPlayed! > 0) {
          lastPlayedMap[s.url] = s.lastPlayed!;
        }
      }
      final storeList = store.list.where(RadioStationStore.isQuranStation);
      final existingUrls = curated.map((c) => c.station.url).toSet();
      final extraItems = <QuranHeroItem>[];
      for (final s in storeList) {
        if (!existingUrls.contains(s.url)) {
          existingUrls.add(s.url);
          extraItems.add(QuranRadioHeroCarousel.buildMergedHeroItem(s));
        }
      }
      if (!mounted) return;
      setState(() {
        _lastPlayedByUrl = lastPlayedMap;
        _baseItems = extraItems.isEmpty ? curated : [...curated, ...extraItems];
        _rebuildOrderedStations();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    if (isArabic != _isArabic || _stations.isEmpty) {
      _isArabic = isArabic;
      _rebuildOrderedStations();
    }
    _syncAutoScrollTimer(PulsrMotion.shouldAnimate(context));
  }

  @override
  void didUpdateWidget(covariant QuranRadioHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoScroll != widget.autoScroll ||
        oldWidget.autoScrollInterval != widget.autoScrollInterval) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      _syncAutoScrollTimer(PulsrMotion.shouldAnimate(context));
    }
  }

  void _syncAutoScrollTimer(bool shouldAnimate) {
    if (!widget.autoScroll || !shouldAnimate || _stations.length <= 1) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      return;
    }
    if (_autoScrollTimer == null || !_autoScrollTimer!.isActive) {
      _autoScrollTimer = Timer.periodic(
        widget.autoScrollInterval,
        (_) => _onAutoScrollTick(),
      );
    }
  }

  void _onAutoScrollTick() {
    if (!mounted ||
        !PulsrMotion.shouldAnimate(context) ||
        !_pageController.hasClients ||
        _stations.length <= 1) {
      return;
    }
    try {
      final player = _resolvePlayerCubit(context);
      if (player.state.isPlaying) return;
    } catch (_) {}
    final nextPage = (_currentPage + 1) % _stations.length;
    _goToPage(nextPage);
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    RadioStationStore.heroPinnedUrls.removeListener(_onOrderPrefsChanged);
    RadioStationStore.heroSortMode.removeListener(_onOrderPrefsChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onOrderPrefsChanged() {
    if (!mounted) return;
    setState(() {
      _rebuildOrderedStations();
    });
  }

  void _rebuildOrderedStations() {
    _stations = QuranRadioHeroCarousel.sortAndPinItems(
      _baseItems,
      pinnedUrls: RadioStationStore.heroPinnedUrls.value,
      sortMode: RadioStationStore.heroSortMode.value,
      isArabic: _isArabic,
      lastPlayedByUrl: _lastPlayedByUrl,
    );
    if (_currentPage >= _stations.length && _stations.isNotEmpty) {
      _currentPage = 0;
    }
  }

  void _goToPage(int page) {
    if (!_pageController.hasClients) return;
    setState(() => _currentPage = page);
    final shouldAnimate = PulsrMotion.shouldAnimate(context);
    final dur = context.motion(PulsrMotion.page);
    if (!shouldAnimate || dur == Duration.zero) {
      _pageController.jumpToPage(page);
    } else {
      _pageController.animateToPage(
        page,
        duration: dur,
        curve: context.motionCurve(PulsrMotion.enter),
      );
    }
  }

  void _jumpToFirstPage() => _goToPage(0);

  PlayerCubit _resolvePlayerCubit(BuildContext context) {
    return widget.playerCubit ?? context.read<PlayerCubit>();
  }

  void _onPlayStation(QuranHeroItem item, bool isCurrent) {
    final playerCubit = _resolvePlayerCubit(context);
    PulsrHaptics.mediumImpact();
    if (isCurrent) {
      playerCubit.togglePlayPause();
    } else {
      final lang = Localizations.localeOf(context).languageCode;
      final localizedStation = item.station.copyWith(
        name: RadioStationStore.localizedStationName(item.station, lang),
      );
      playerCubit.playRadioStation(localizedStation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _stations.length;
    final shouldAnimate = PulsrMotion.shouldAnimate(context);
    _syncAutoScrollTimer(shouldAnimate);
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.2);
    final baseHeight = math.max(widget.height, 164.0);
    final effectiveHeight = baseHeight + (textScale - 1.0) * 96.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Swipeable mihrab cards ──────────────────────────────────────────
        SizedBox(
          height: effectiveHeight,
          child: PageView.builder(
            key: const PageStorageKey('quran_radio_hero_carousel_pv'),
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            padEnds: false,
            itemCount: total,
            onPageChanged: (index) {
              if (index != _currentPage) {
                PulsrHaptics.selectionClick();
                setState(() => _currentPage = index);
              }
            },
            itemBuilder: (context, index) {
              final item = _stations[index];
              final cardChild = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _QuranHeroCard(
                  item: item,
                  pageController: _pageController,
                  pageIndex: index,
                  isPinned: RadioStationStore.heroPinnedUrls.value
                      .contains(item.station.url),
                  onTap: () {
                    final player = _resolvePlayerCubit(context);
                    final isCurrent =
                        player.state.currentSong?.path == item.station.url;
                    _onPlayStation(item, isCurrent);
                  },
                  onPlayPressed: (isCurrent) => _onPlayStation(item, isCurrent),
                  onLongPress: () {
                    PulsrHaptics.heavyImpact();
                    _showCardOptionsSheet(context, item);
                  },
                ),
              );
              if (!shouldAnimate) return cardChild;
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double value = 0.0;
                  if (_pageController.hasClients &&
                      _pageController.position.haveDimensions) {
                    final page = _pageController.page ??
                        _pageController.initialPage.toDouble();
                    value = (page - index).clamp(-1.0, 1.0).toDouble();
                  } else {
                    value = (_currentPage - index)
                        .toDouble()
                        .clamp(-1.0, 1.0)
                        .toDouble();
                  }
                  final scale = 1.0 - (value.abs() * 0.045);
                  final opacity =
                      (1.0 - (value.abs() * 0.18)).clamp(0.82, 1.0).toDouble();
                  return Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity,
                      child: child,
                    ),
                  );
                },
                child: cardChild,
              );
            },
          ),
        ),
        if (total > 1) ...[
          const SizedBox(height: AppSpacing.s6),
          Center(
            child: _CarouselWindowedDots(
              total: total,
              currentPage: _currentPage,
              onDotTap: (i) {
                PulsrHaptics.selectionClick();
                _goToPage(i);
              },
            ),
          ),
        ],
      ],
    );
  }

  void _showCardOptionsSheet(BuildContext context, QuranHeroItem item) {
    final p = context.palette;
    final gilt = _giltOf(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final stationTitle = item.getReciterTitle(isArabic);
    final stationUrl = item.station.url;

    PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: ValueListenableBuilder<List<String>>(
            valueListenable: RadioStationStore.heroPinnedUrls,
            builder: (context, pinnedUrls, _) {
              return ValueListenableBuilder<QuranHeroSortMode>(
                valueListenable: RadioStationStore.heroSortMode,
                builder: (context, activeSort, _) {
                  final isPinned = pinnedUrls.contains(stationUrl);
                  final isPinnedFirst =
                      pinnedUrls.isNotEmpty && pinnedUrls.first == stationUrl;
                  final hasCustomOrder = pinnedUrls.isNotEmpty ||
                      activeSort != QuranHeroSortMode.curated;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Illuminated header: arch thumbnail + titles ───────
                      Row(
                        children: [
                          _ArchThumb(item: item, width: 44, height: 54),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.radioCardsTitle,
                                  style: TextStyle(
                                    color: p.textPrimary,
                                    fontSize: AppFontSize.title,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  stationTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.caption,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isPinned) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: gilt.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: gilt.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: Icon(
                                Icons.push_pin_rounded,
                                size: 13,
                                color: gilt,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _OrnamentDivider(),
                      const SizedBox(height: AppSpacing.sm),
                      // ── Pin to First / Unpin action ───────────────────────
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.r14All,
                          side: BorderSide(
                            color: p.accent.withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        tileColor: p.accent.withValues(alpha: 0.10),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.14),
                            borderRadius: AppRadii.r12All,
                          ),
                          child: Icon(
                            isPinnedFirst
                                ? Icons.push_pin_outlined
                                : Icons.push_pin_rounded,
                            color: p.accent,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          isPinnedFirst
                              ? context.l10n.unpinRadioCard
                              : context.l10n.pinRadioCardToFirst,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.bodySmall,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          isPinnedFirst
                              ? context.l10n.unpinRadioCardSubtitle
                              : context.l10n.pinRadioCardToFirstSubtitle,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.caption,
                          ),
                        ),
                        trailing: (isPinned && !isPinnedFirst)
                            ? TextButton(
                                onPressed: () async {
                                  PulsrHaptics.selectionClick();
                                  Navigator.of(sheetContext).pop();
                                  await RadioStationStore.unpinHeroCard(
                                      stationUrl);
                                  if (context.mounted) {
                                    PulsrToast.show(
                                      context,
                                      message:
                                          context.l10n.radioCardUnpinnedToast,
                                      isSuccess: true,
                                    );
                                  }
                                },
                                child: Text(
                                  context.l10n.unpinRadioCard,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.caption,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            : null,
                        onTap: () async {
                          PulsrHaptics.selectionClick();
                          Navigator.of(sheetContext).pop();
                          if (isPinnedFirst) {
                            await RadioStationStore.unpinHeroCard(stationUrl);
                            if (mounted) _jumpToFirstPage();
                            if (context.mounted) {
                              PulsrToast.show(
                                context,
                                message: context.l10n.radioCardUnpinnedToast,
                                isSuccess: true,
                              );
                            }
                          } else {
                            await RadioStationStore.pinHeroCardFirst(
                                stationUrl);
                            if (mounted) _jumpToFirstPage();
                            if (context.mounted) {
                              PulsrToast.show(
                                context,
                                message: context.l10n.radioCardPinnedToast,
                                isSuccess: true,
                              );
                            }
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // ── Sort order header + optional reset ────────────────
                      Row(
                        children: [
                          _StarGlyph(size: 10, color: gilt),
                          const SizedBox(width: 6),
                          Text(
                            context.l10n.sortRadioCardsTitle,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const Spacer(),
                          if (hasCustomOrder)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                              ),
                              onPressed: () async {
                                PulsrHaptics.selectionClick();
                                await RadioStationStore.resetHeroCardOrder();
                                if (mounted) _jumpToFirstPage();
                                if (context.mounted) {
                                  PulsrToast.show(
                                    context,
                                    message:
                                        context.l10n.radioCardOrderResetToast,
                                    isSuccess: true,
                                  );
                                }
                              },
                              icon: Icon(
                                Icons.restart_alt_rounded,
                                size: 15,
                                color: p.accent,
                              ),
                              label: Text(
                                context.l10n.resetRadioCardOrder,
                                style: TextStyle(
                                  color: p.accent,
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // ── Sort mode selector row ────────────────────────────
                      Row(
                        children: [
                          _SortOptionChip(
                            icon: Icons.auto_awesome_rounded,
                            label: context.l10n.sortRadioCardsDefault,
                            selected: activeSort == QuranHeroSortMode.curated,
                            onTap: () async {
                              PulsrHaptics.selectionClick();
                              await RadioStationStore.setHeroSortMode(
                                  QuranHeroSortMode.curated);
                              if (mounted) _jumpToFirstPage();
                            },
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _SortOptionChip(
                            icon: Icons.sort_by_alpha_rounded,
                            label: context.l10n.sortRadioCardsAlphabetical,
                            selected:
                                activeSort == QuranHeroSortMode.alphabetical,
                            onTap: () async {
                              PulsrHaptics.selectionClick();
                              await RadioStationStore.setHeroSortMode(
                                  QuranHeroSortMode.alphabetical);
                              if (mounted) _jumpToFirstPage();
                            },
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _SortOptionChip(
                            icon: Icons.history_rounded,
                            label: context.l10n.sortRadioCardsRecent,
                            selected:
                                activeSort == QuranHeroSortMode.recentlyPlayed,
                            onTap: () async {
                              PulsrHaptics.selectionClick();
                              await RadioStationStore.setHeroSortMode(
                                  QuranHeroSortMode.recentlyPlayed);
                              if (mounted) _jumpToFirstPage();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // ── Hide action ───────────────────────────────────────
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.r14All,
                        ),
                        tileColor:
                            p.surfaceContainerHigh.withValues(alpha: 0.5),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: p.favorite.withValues(alpha: 0.12),
                            borderRadius: AppRadii.r12All,
                          ),
                          child: Icon(
                            Icons.visibility_off_rounded,
                            color: p.favorite,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          context.l10n.hideRadioCardsFromHome,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.bodySmall,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.radioCardsRestoreHint,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.caption,
                          ),
                        ),
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          await RadioStationStore.setHeroCardsVisible(false);
                          if (context.mounted) {
                            PulsrToast.show(
                              context,
                              message: context.l10n.radioCardsHiddenToast,
                              isSuccess: true,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The individual mihrab hero card for a single Quran station.
class _QuranHeroCard extends StatelessWidget {
  final QuranHeroItem item;
  final PageController pageController;
  final int pageIndex;
  final bool isPinned;
  final VoidCallback onTap;
  final void Function(bool isCurrent) onPlayPressed;
  final VoidCallback onLongPress;

  const _QuranHeroCard({
    required this.item,
    required this.pageController,
    required this.pageIndex,
    required this.isPinned,
    required this.onTap,
    required this.onPlayPressed,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final gilt = _giltOf(context);
    final onGilt = _onGilt(gilt);
    final isCapsule = context.isCapsuleButtons;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) {
        final wasCurrent = prev.currentSong?.path == item.station.url;
        final isCurrent = curr.currentSong?.path == item.station.url;
        return wasCurrent != isCurrent ||
            (isCurrent &&
                (prev.isPlaying != curr.isPlaying ||
                    prev.isBuffering != curr.isBuffering ||
                    prev.currentSong?.album != curr.currentSong?.album));
      },
      builder: (context, playerState) {
        final isArabic = Localizations.localeOf(context).languageCode == 'ar';
        final isCurrent = playerState.currentSong?.path == item.station.url;
        final isPlaying = isCurrent && playerState.isPlaying;
        final isBuffering = isCurrent && playerState.isBuffering;
        final rawIcyTitle =
            isCurrent ? (playerState.currentSong?.album.trim() ?? '') : '';
        final defaultSubtitle = item.getSubtitle(isArabic);
        final displaySubtitle =
            rawIcyTitle.isNotEmpty ? rawIcyTitle : defaultSubtitle;
        final reciterTitle = item.getReciterTitle(isArabic);
        final badgeText = item.getBadgeText(isArabic);
        final defaultBadge = context.l10n.holyQuranRadio;

        // Cool accent wash on the editorial side, warm gilt wash toward the niche.
        final surfaceStart = Color.alphaBlend(
          p.accent.withValues(alpha: p.isDark ? 0.085 : 0.055),
          p.surfaceContainerHigh,
        );
        final surfaceEnd = Color.alphaBlend(
          gilt.withValues(alpha: p.isDark ? 0.08 : 0.05),
          p.surfaceContainer,
        );
        final isHomeCard = item.artworkAsset.contains('home card') ||
            item.artworkAsset.contains('home_card');
        final isNetwork = item.artworkAsset.startsWith('http://') ||
            item.artworkAsset.startsWith('https://');
        final ctaRadius = isCapsule
            ? context.buttonRadius(rectRadius: 12.0)
            : AppRadii.circular(999);

        return Semantics(
          button: true,
          label: '$reciterTitle, $displaySubtitle. '
              '${isPlaying ? context.l10n.radioNowPlayingSemantics : context.l10n.radioTapToPlaySemantics}',
          child: Material(
            color: AppColors.fadeStopTransparent,
            borderRadius: AppRadii.r24All,
            child: InkWell(
              borderRadius: AppRadii.r24All,
              onTap: onTap,
              onLongPress: onLongPress,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [surfaceStart, surfaceEnd],
                  ),
                  borderRadius: AppRadii.r24All,
                  boxShadow: p.isCalmDensity
                      ? null
                      : (isPlaying
                          ? [
                              BoxShadow(
                                color: p.accent.withValues(alpha: 0.24),
                                blurRadius: 22,
                                spreadRadius: -2,
                                offset: const Offset(0, 6),
                              ),
                              ...PulsrElevation.level2(context),
                            ]
                          : PulsrElevation.level2(context)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 500;
                    final isCompact = constraints.maxWidth < 310;
                    final archFraction =
                        isWide ? 0.33 : (isCompact ? 0.34 : 0.35);
                    final archWidth = (constraints.maxWidth * archFraction)
                        .clamp(104.0, 168.0)
                        .toDouble();
                    const archEndInset = 8.0;
                    const textArchGap = 14.0;
                    final trailingReserved =
                        archWidth + archEndInset + textArchGap;
                    final leadingPadding = isCompact ? 14.0 : 16.0;
                    final textDir = Directionality.of(context);

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // Etched khatam lattice — static, repaint-bounded.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: _KhatamLatticePainter(
                                    color: gilt.withValues(
                                      alpha: p.isDark ? 0.05 : 0.045,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Warm ambient aura behind the niche.
                        if (!p.isCalmDensity)
                          PositionedDirectional(
                            end: -16,
                            top: -16,
                            bottom: -16,
                            width: archWidth + 36,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    colors: [
                                      gilt.withValues(
                                        alpha: isPlaying ? 0.24 : 0.13,
                                      ),
                                      AppColors.fadeStopTransparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // ── Mihrab niche: arch-clipped artwork + gilt rim ────
                        PositionedDirectional(
                          end: archEndInset,
                          top: 8,
                          bottom: 8,
                          width: archWidth,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipPath(
                                clipper: _MihrabClipper(),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (isNetwork)
                                      CachedArtwork(
                                        id: 0,
                                        remoteUrl: item.artworkAsset,
                                        size: archWidth,
                                        fallbackIcon: Icons.radio_rounded,
                                      )
                                    else
                                      // Parallax framing: the panoramic scene
                                      // drifts gently against the swipe.
                                      AnimatedBuilder(
                                        animation: pageController,
                                        builder: (context, _) {
                                          double v = 0.0;
                                          if (PulsrMotion.shouldAnimate(
                                                  context) &&
                                              pageController.hasClients &&
                                              pageController
                                                  .position.haveDimensions) {
                                            v = ((pageController.page ??
                                                        pageController
                                                            .initialPage
                                                            .toDouble()) -
                                                    pageIndex)
                                                .clamp(-1.0, 1.0)
                                                .toDouble();
                                          }
                                          final ax = isHomeCard
                                              ? (1.0 - v * 0.30)
                                                  .clamp(-1.0, 1.0)
                                                  .toDouble()
                                              : (v * -0.25)
                                                  .clamp(-1.0, 1.0)
                                                  .toDouble();
                                          return Image.asset(
                                            item.artworkAsset,
                                            fit: BoxFit.cover,
                                            alignment: Alignment(
                                              ax,
                                              isHomeCard ? 0.0 : -0.15,
                                            ),
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                              color: p.accentContainer
                                                  .withValues(alpha: 0.2),
                                              child: Icon(
                                                Icons.radio_rounded,
                                                size: 44,
                                                color: p.accent
                                                    .withValues(alpha: 0.3),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    // Directional leading-edge fade blends the
                                    // arched artwork organically into the canvas
                                    // (mirrors automatically in RTL).
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin:
                                              AlignmentDirectional.centerStart,
                                          end: AlignmentDirectional.centerEnd,
                                          colors: [
                                            surfaceEnd.withValues(
                                              alpha: p.isDark ? 0.60 : 0.38,
                                            ),
                                            surfaceEnd.withValues(
                                              alpha: p.isDark ? 0.20 : 0.10,
                                            ),
                                            AppColors.fadeStopTransparent,
                                          ],
                                          stops: const [0.0, 0.24, 0.56],
                                        ),
                                      ),
                                    ),
                                    // Depth scrim toward the niche floor.
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            AppColors.fadeStopTransparent,
                                            surfaceEnd.withValues(
                                              alpha: p.isDark ? 0.40 : 0.18,
                                            ),
                                          ],
                                          stops: const [0.56, 1.0],
                                        ),
                                      ),
                                    ),
                                    if (isPlaying)
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color:
                                              p.accent.withValues(alpha: 0.05),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Animated directional gilt rim + broadcast glow.
                              IgnorePointer(
                                child: TweenAnimationBuilder<double>(
                                  tween:
                                      Tween<double>(end: isPlaying ? 1.0 : 0.0),
                                  duration: context.motion(PulsrMotion.layout),
                                  builder: (context, glow, _) {
                                    return CustomPaint(
                                      painter: _MihrabRimPainter(
                                        color: gilt,
                                        glow: p.isCalmDensity ? 0.0 : glow,
                                        textDirection: textDir,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Top specular hairline with a gilt heart.
                        PositionedDirectional(
                          top: 0,
                          start: 18,
                          end: 18,
                          child: IgnorePointer(
                            child: Container(
                              height: 1.0,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.fadeStopTransparent,
                                    p.isDark
                                        ? AppColors.specularAt(0.11)
                                        : AppColors.scrimAt(0.04),
                                    gilt.withValues(
                                        alpha: isPlaying ? 0.58 : 0.34),
                                    p.isDark
                                        ? AppColors.specularAt(0.11)
                                        : AppColors.scrimAt(0.04),
                                    AppColors.fadeStopTransparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Large star seal watermark on the leading floor.
                        PositionedDirectional(
                          start: -16,
                          bottom: -20,
                          child: ExcludeSemantics(
                            child: _StarGlyph(
                              size: 96,
                              color: p.accent
                                  .withValues(alpha: isPlaying ? 0.07 : 0.04),
                            ),
                          ),
                        ),
                        // ── Editorial column ─────────────────────────────────
                        ClipRect(
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(
                              leadingPadding,
                              12,
                              trailingReserved,
                              12,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Overline: live badge / category seal + pin.
                                Row(
                                  children: [
                                    Flexible(
                                      child: AnimatedSwitcher(
                                        duration:
                                            context.motion(PulsrMotion.layout),
                                        child: Container(
                                          key: ValueKey<bool>(isPlaying),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isPlaying
                                                ? p.accent
                                                    .withValues(alpha: 0.18)
                                                : p.accent
                                                    .withValues(alpha: 0.10),
                                            borderRadius:
                                                AppRadii.circular(999),
                                            border: Border.all(
                                              color: p.accent.withValues(
                                                alpha: isPlaying ? 0.42 : 0.22,
                                              ),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isPlaying) ...[
                                                const _PulsingLiveDot(),
                                                const SizedBox(width: 5),
                                                Flexible(
                                                  child: Text(
                                                    context.l10n
                                                        .radioLiveOnAirBadge,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: p.accent,
                                                      fontSize:
                                                          AppFontSize.caption,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 0.45,
                                                    ),
                                                  ),
                                                ),
                                              ] else ...[
                                                _StarGlyph(
                                                  size: 10,
                                                  color: p.accent,
                                                ),
                                                const SizedBox(width: 4.5),
                                                Flexible(
                                                  child: Text(
                                                    badgeText ?? defaultBadge,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: p.accent,
                                                      fontSize:
                                                          AppFontSize.caption,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      letterSpacing: 0.3,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (isPinned) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: gilt.withValues(alpha: 0.14),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: gilt.withValues(alpha: 0.35),
                                            width: 0.7,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.push_pin_rounded,
                                          size: 10,
                                          color: gilt,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // Station / reciter editorial 2-line title.
                                Text(
                                  reciterTitle,
                                  key: ValueKey('hero_title_${item.station.id}'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.start,
                                  textDirection: isArabic
                                      ? TextDirection.rtl
                                      : TextDirection.ltr,
                                  style: TextStyle(
                                    color: p.textPrimary,
                                    fontSize: AppFontSize.bodyLarge,
                                    fontWeight: FontWeight.w800,
                                    height: 1.18,
                                    letterSpacing: AppTracking.title,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Subtitle / live ICY surah readout.
                                Row(
                                  children: [
                                    if (isPlaying)
                                      Padding(
                                        padding:
                                            const EdgeInsetsDirectional.only(
                                                end: 4.5),
                                        child: Icon(
                                          Icons.graphic_eq_rounded,
                                          size: 13,
                                          color: p.accent,
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        displaySubtitle,
                                        key: ValueKey(
                                            'hero_sub_${item.station.id}'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.start,
                                        textDirection: isArabic
                                            ? TextDirection.rtl
                                            : TextDirection.ltr,
                                        style: TextStyle(
                                          color: isPlaying
                                              ? p.accent
                                              : p.textSecondary,
                                          fontSize: AppFontSize.label,
                                          fontWeight: isPlaying
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // ── Gilt transport row ─────────────────────────
                                Row(
                                  children: [
                                    Flexible(
                                      child: ExcludeSemantics(
                                        child: Material(
                                          color: AppColors.fadeStopTransparent,
                                          child: InkWell(
                                            borderRadius: ctaRadius,
                                            onTap: () =>
                                                onPlayPressed(isCurrent),
                                            child: Container(
                                              constraints: const BoxConstraints(
                                                minHeight: 35,
                                              ),
                                              padding:
                                                  EdgeInsetsDirectional
                                                      .fromSTEB(
                                                isPlaying ? 11 : 10,
                                                5,
                                                isPlaying ? 11 : 14,
                                                5,
                                              ),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: AlignmentDirectional
                                                      .topStart,
                                                  end: AlignmentDirectional
                                                      .bottomEnd,
                                                  colors: [
                                                    Color.alphaBlend(
                                                      AppColors.specularAt(
                                                          0.14),
                                                      gilt,
                                                    ),
                                                    gilt,
                                                    Color.alphaBlend(
                                                      AppColors.scrimAt(0.10),
                                                      gilt,
                                                    ),
                                                  ],
                                                  stops: const [0.0, 0.48, 1.0],
                                                ),
                                                borderRadius: ctaRadius,
                                                boxShadow: p.isCalmDensity
                                                    ? null
                                                    : [
                                                        BoxShadow(
                                                          color: gilt.withValues(
                                                            alpha: isPlaying
                                                                ? 0.34
                                                                : 0.22,
                                                          ),
                                                          blurRadius: 10,
                                                          offset: const Offset(0, 3),
                                                        ),
                                                        BoxShadow(
                                                          color: AppColors.scrimAt(
                                                            p.isDark ? 0.28 : 0.12,
                                                          ),
                                                          blurRadius: 4,
                                                          offset: const Offset(0, 1),
                                                        ),
                                                      ],
                                                border: Border.all(
                                                  color: onGilt.withValues(
                                                    alpha: isPlaying
                                                        ? 0.28
                                                        : 0.14,
                                                  ),
                                                  width: 0.85,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (isBuffering)
                                                    const SkeletonShimmer(
                                                      child: SkeletonBox(
                                                        width: 14,
                                                        height: 14,
                                                        radius: 7,
                                                      ),
                                                    )
                                                  else
                                                    Icon(
                                                      isPlaying
                                                          ? Icons.pause_rounded
                                                          : Icons
                                                              .play_arrow_rounded,
                                                      color: onGilt,
                                                      size: 19,
                                                    ),
                                                  if (!isPlaying) ...[
                                                    const SizedBox(width: 5),
                                                    Flexible(
                                                      child: Text(
                                                        context
                                                            .l10n.radioListenNow,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          color: onGilt,
                                                          fontSize:
                                                              AppFontSize.label,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          letterSpacing: 0.1,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (isPlaying) ...[
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            minHeight: 34,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                p.accent.withValues(alpha: 0.14),
                                            borderRadius: ctaRadius,
                                            border: Border.all(
                                              color:
                                                  p.accent.withValues(alpha: 0.35),
                                              width: 0.85,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _MiniEqualizerBars(
                                                isPlaying: true,
                                                color: p.accent,
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  context
                                                      .l10n.radioLiveShortBadge,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: p.accent,
                                                    fontSize: AppFontSize.caption,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Animated outer border: hairline at rest, accent on air.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedContainer(
                              duration: context.motion(PulsrMotion.layout),
                              decoration: BoxDecoration(
                                borderRadius: AppRadii.r24All,
                                border: Border.all(
                                  color: isPlaying
                                      ? p.accent.withValues(alpha: 0.72)
                                      : Color.alphaBlend(
                                          gilt.withValues(
                                            alpha: p.isDark ? 0.16 : 0.22,
                                          ),
                                          p.hairline,
                                        ),
                                  width: isPlaying ? 1.4 : 0.9,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
