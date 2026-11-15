import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/services/radio_station_store.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/theme/pulsr_button_style.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../domain/models/radio_station.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import '../../../../core/utils/pulsr_haptics.dart';

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

  const QuranRadioHeroCarousel({
    super.key,
    this.playerCubit,
    this.height = 152.0,
    this.onMoreStations,
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
  }

  @override
  void dispose() {
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

  void _jumpToFirstPage() {
    if (!_pageController.hasClients) return;
    setState(() => _currentPage = 0);
    final dur = context.motion(PulsrMotion.page);
    if (dur == Duration.zero) {
      _pageController.jumpToPage(0);
    } else {
      _pageController.animateToPage(
        0,
        duration: dur,
        curve: context.motionCurve(PulsrMotion.enter),
      );
    }
  }

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
    final p = context.palette;
    final gilt = _giltOf(context);
    final total = _stations.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Swipeable mihrab cards ──────────────────────────────────────────
        SizedBox(
          height: widget.height,
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
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double value = 0.0;
                  if (_pageController.position.haveDimensions) {
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
                child: Padding(
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
                    onPlayPressed: (isCurrent) =>
                        _onPlayStation(item, isCurrent),
                    onLongPress: () {
                      PulsrHaptics.heavyImpact();
                      _showCardOptionsSheet(context, item);
                    },
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        // ── Indicator strip: diamond window + tabular counter + radio chip ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0),
          child: Row(
            children: [
              _CarouselWindowedDots(
                total: total,
                currentPage: _currentPage,
                onDotTap: (i) {
                  PulsrHaptics.selectionClick();
                  final dur = context.motion(PulsrMotion.page);
                  if (dur == Duration.zero) {
                    _pageController.jumpToPage(i);
                  } else {
                    _pageController.animateToPage(
                      i,
                      duration: dur,
                      curve: context.motionCurve(PulsrMotion.enter),
                    );
                  }
                },
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6.0,
                  vertical: 2.0,
                ),
                decoration: BoxDecoration(
                  color: p.surfaceContainer.withValues(alpha: 0.9),
                  borderRadius: AppRadii.r6All,
                  border: Border.all(
                    color: p.hairline.withValues(alpha: 0.8),
                    width: 0.7,
                  ),
                ),
                child: Text(
                  '${_currentPage + 1}/$total',
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Quick "All Stations" tonal action chip
              Semantics(
                button: true,
                label: context.l10n.viewAllRadioStations,
                child: Material(
                  color: Colors.transparent,
                  child: Builder(
                    builder: (context) {
                      final isCapsule = context.isCapsuleButtons;
                      final radius = context.buttonRadius(rectRadius: 10.0);
                      return InkWell(
                        borderRadius: radius,
                        onTap: widget.onMoreStations ??
                            () {
                              PulsrHaptics.selectionClick();
                              context.push('/radio');
                            },
                        child: Container(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            9.0,
                            4.5,
                            6.0,
                            4.5,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                p.accent.withValues(alpha: 0.16),
                                gilt.withValues(alpha: 0.10),
                              ],
                            ),
                            borderRadius:
                                isCapsule ? radius : AppRadii.circular(999),
                            border: Border.all(
                              color: p.accent.withValues(alpha: 0.28),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.radio_rounded,
                                size: 12.5,
                                color: p.accent,
                              ),
                              const SizedBox(width: 4.5),
                              Text(
                                context.l10n.radioTitle,
                                style: TextStyle(
                                  color: p.accent,
                                  fontSize: 11.0,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(width: 1),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 14,
                                color: p.accent.withValues(alpha: 0.85),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
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
                            fontSize: AppFontSize.tiny,
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
                            fontSize: AppFontSize.tiny,
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

// ─────────────────────────────────────────────────────────────────────────────
// Illumination palette: manuscript gilt derived from the active theme accent,
// so ornamentation stays coherent across all ten Pulsr themes.
// ─────────────────────────────────────────────────────────────────────────────

Color _giltOf(BuildContext context) {
  final p = context.palette;
  return Color.lerp(
    p.accent,
    const Color(0xFFC9A24B),
    p.isDark ? 0.58 : 0.50,
  )!;
}

Color _onGilt(Color gilt) {
  return ThemeData.estimateBrightnessForColor(gilt) == Brightness.dark
      ? const Color(0xFFFFF7E6)
      : const Color(0xFF231A06);
}

// ─────────────────────────────────────────────────────────────────────────────
// Geometry: eight-pointed khatam star + pointed mihrab arch path.
// ─────────────────────────────────────────────────────────────────────────────

Path _eightPointStarPath(Offset center, double radius) {
  const points = 8;
  final inner = radius * 0.46;
  final path = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? radius : inner;
    final a = -math.pi / 2 + i * math.pi / points;
    final pt = Offset(
      center.dx + r * math.cos(a),
      center.dy + r * math.sin(a),
    );
    if (i == 0) {
      path.moveTo(pt.dx, pt.dy);
    } else {
      path.lineTo(pt.dx, pt.dy);
    }
  }
  path.close();
  return path;
}

Path _mihrabPath(double w, double h) {
  final shoulder = h * 0.34;
  const r = 12.0;
  final path = Path()
    ..moveTo(0, h - r)
    ..lineTo(0, shoulder)
    ..cubicTo(0, h * 0.12, w * 0.22, h * 0.045, w / 2, 0)
    ..cubicTo(w * 0.78, h * 0.045, w, h * 0.12, w, shoulder)
    ..lineTo(w, h - r)
    ..quadraticBezierTo(w, h, w - r, h)
    ..lineTo(r, h)
    ..quadraticBezierTo(0, h, 0, h - r)
    ..close();
  return path;
}

class _MihrabClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => _mihrabPath(size.width, size.height);

  @override
  bool shouldReclip(covariant _MihrabClipper oldClipper) => false;
}

/// Gilt rim stroked over the arch aperture, with a soft broadcast glow and a
/// finial bead at the apex. [glow] animates 0→1 while the station is on air.
class _MihrabRimPainter extends CustomPainter {
  final Color color;
  final double glow;

  const _MihrabRimPainter({required this.color, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final path = _mihrabPath(size.width, size.height);
    if (glow > 0.01) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = color.withValues(alpha: 0.30 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = color.withValues(alpha: 0.55 + 0.35 * glow),
    );
    canvas.drawCircle(
      Offset(size.width / 2, 2.2),
      2.0,
      Paint()..color = color.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _MihrabRimPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.glow != glow;
}

/// Faint eight-fold star lattice etched across the card surface — painted once
/// inside a [RepaintBoundary], never per scroll frame.
class _KhatamLatticePainter extends CustomPainter {
  static const double cell = 46.0;
  final Color color;

  const _KhatamLatticePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final star = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = color;
    final dot = Paint()..color = color;
    for (double y = cell / 2; y < size.height + cell; y += cell) {
      for (double x = cell / 2; x < size.width + cell; x += cell) {
        canvas.drawPath(_eightPointStarPath(Offset(x, y), cell * 0.30), star);
      }
    }
    for (double y = 0; y <= size.height + cell; y += cell) {
      for (double x = 0; x <= size.width + cell; x += cell) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KhatamLatticePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Small filled eight-point star used as a station seal / ornamental glyph.
class _StarGlyph extends StatelessWidget {
  final double size;
  final Color color;

  const _StarGlyph({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _StarFillPainter(color)),
    );
  }
}

class _StarFillPainter extends CustomPainter {
  final Color color;

  const _StarFillPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _eightPointStarPath(
        Offset(size.width / 2, size.height / 2),
        math.min(size.width, size.height) / 2,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _StarFillPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Hairline rule interrupted by a gilt diamond and flanking beads.
class _OrnamentDivider extends StatelessWidget {
  const _OrnamentDivider();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 12,
      width: double.infinity,
      child: CustomPaint(
        painter: _OrnamentDividerPainter(
          line: p.hairline,
          ornament: _giltOf(context),
        ),
      ),
    );
  }
}

class _OrnamentDividerPainter extends CustomPainter {
  final Color line;
  final Color ornament;

  const _OrnamentDividerPainter({required this.line, required this.ornament});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final cx = size.width / 2;
    final lp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = line;
    canvas.drawLine(Offset(0, y), Offset(cx - 14, y), lp);
    canvas.drawLine(Offset(cx + 14, y), Offset(size.width, y), lp);
    final diamond = Path()
      ..moveTo(cx, y - 4)
      ..lineTo(cx + 4, y)
      ..lineTo(cx, y + 4)
      ..lineTo(cx - 4, y)
      ..close();
    canvas.drawPath(diamond, Paint()..color = ornament);
    final bead = Paint()..color = ornament.withValues(alpha: 0.7);
    canvas.drawCircle(Offset(cx - 9, y), 1.1, bead);
    canvas.drawCircle(Offset(cx + 9, y), 1.1, bead);
  }

  @override
  bool shouldRepaint(covariant _OrnamentDividerPainter oldDelegate) =>
      oldDelegate.line != line || oldDelegate.ornament != ornament;
}

/// Miniature arch-framed artwork used in the options sheet header.
class _ArchThumb extends StatelessWidget {
  final QuranHeroItem item;
  final double width;
  final double height;

  const _ArchThumb({
    required this.item,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isNetwork = item.artworkAsset.startsWith('http://') ||
        item.artworkAsset.startsWith('https://');
    final isHomeCard = item.artworkAsset.contains('home card') ||
        item.artworkAsset.contains('home_card');
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipPath(
            clipper: _MihrabClipper(),
            child: isNetwork
                ? CachedArtwork(
                    id: 0,
                    remoteUrl: item.artworkAsset,
                    size: width,
                    fallbackIcon: Icons.radio_rounded,
                  )
                : Image.asset(
                    item.artworkAsset,
                    fit: BoxFit.cover,
                    alignment: isHomeCard
                        ? Alignment.centerRight
                        : const Alignment(0.0, -0.15),
                    errorBuilder: (_, __, ___) => Container(
                      color: p.accentContainer.withValues(alpha: 0.2),
                      child: Icon(
                        Icons.radio_rounded,
                        size: 20,
                        color: p.accent.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _MihrabRimPainter(color: _giltOf(context), glow: 0),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tactile pill selector for radio card sorting options inside the long-press sheet.
class _SortOptionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortOptionChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.r12All,
        child: InkWell(
          borderRadius: AppRadii.r12All,
          onTap: onTap,
          child: AnimatedContainer(
            duration: context.motion(PulsrMotion.layout),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? p.accent.withValues(alpha: 0.16)
                  : p.surfaceContainerHigh.withValues(alpha: 0.55),
              borderRadius: AppRadii.r12All,
              border: Border.all(
                color: selected
                    ? p.accent.withValues(alpha: 0.60)
                    : p.hairline.withValues(alpha: 0.7),
                width: selected ? 1.2 : 0.8,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? p.accent : p.textSecondary,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? p.accent : p.textPrimary,
                    fontSize: AppFontSize.tiny,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
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
          p.accent.withValues(alpha: p.isDark ? 0.09 : 0.06),
          p.surfaceContainerHigh,
        );
        final surfaceEnd = Color.alphaBlend(
          gilt.withValues(alpha: p.isDark ? 0.05 : 0.035),
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
            color: Colors.transparent,
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
                  boxShadow: isPlaying
                      ? [
                          BoxShadow(
                            color: p.accent.withValues(alpha: 0.24),
                            blurRadius: 22,
                            spreadRadius: -2,
                            offset: const Offset(0, 6),
                          ),
                          ...PulsrElevation.level2(context),
                        ]
                      : PulsrElevation.level2(context),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final archWidth = (constraints.maxWidth * 0.42)
                        .clamp(128.0, 190.0)
                        .toDouble();
                    final trailingReserved = archWidth + 24.0;

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
                                      alpha: p.isDark ? 0.055 : 0.05,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Warm ambient aura behind the niche.
                        PositionedDirectional(
                          end: -16,
                          top: -16,
                          bottom: -16,
                          width: archWidth + 32,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  colors: [
                                    gilt.withValues(
                                        alpha: isPlaying ? 0.24 : 0.12),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // ── Mihrab niche: arch-clipped artwork + gilt rim ────
                        PositionedDirectional(
                          end: 8,
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
                                          if (pageController.hasClients &&
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
                                    // Depth scrim toward the niche floor.
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            surfaceEnd.withValues(
                                              alpha: p.isDark ? 0.34 : 0.16,
                                            ),
                                          ],
                                          stops: const [0.55, 1.0],
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
                              // Animated gilt rim + broadcast glow.
                              IgnorePointer(
                                child: TweenAnimationBuilder<double>(
                                  tween:
                                      Tween<double>(end: isPlaying ? 1.0 : 0.0),
                                  duration: context.motion(PulsrMotion.layout),
                                  builder: (context, glow, _) {
                                    return CustomPaint(
                                      painter: _MihrabRimPainter(
                                        color: gilt,
                                        glow: glow,
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
                                    Colors.transparent,
                                    (p.isDark ? Colors.white : Colors.black)
                                        .withValues(
                                            alpha: p.isDark ? 0.14 : 0.05),
                                    gilt.withValues(
                                        alpha: isPlaying ? 0.65 : 0.40),
                                    (p.isDark ? Colors.white : Colors.black)
                                        .withValues(
                                            alpha: p.isDark ? 0.14 : 0.05),
                                    Colors.transparent,
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
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                            AppSpacing.md,
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
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isPlaying
                                              ? p.accent.withValues(alpha: 0.18)
                                              : p.accent
                                                  .withValues(alpha: 0.11),
                                          borderRadius: AppRadii.circular(999),
                                          border: Border.all(
                                            color: p.accent.withValues(
                                              alpha: isPlaying ? 0.45 : 0.24,
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
                                                  context
                                                      .l10n.radioLiveOnAirBadge,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: p.accent,
                                                    fontSize: AppFontSize.tiny,
                                                    fontWeight: FontWeight.w800,
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
                                                    fontSize: AppFontSize.tiny,
                                                    fontWeight: FontWeight.w700,
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
                              const SizedBox(height: 7),
                              // Station / reciter title.
                              MarqueeText(
                                text: reciterTitle,
                                textAlign: TextAlign.start,
                                allowUserPause: false,
                                showTooltip: false,
                                velocity: 28.0,
                                blankSpace: 36.0,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                  letterSpacing: -0.25,
                                ),
                              ),
                              const SizedBox(height: 3),
                              // Subtitle / live ICY surah ticker.
                              Row(
                                children: [
                                  if (isPlaying)
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                          end: 4.5),
                                      child: Icon(
                                        Icons.graphic_eq_rounded,
                                        size: 13,
                                        color: p.accent,
                                      ),
                                    ),
                                  Expanded(
                                    child: MarqueeText(
                                      text: displaySubtitle,
                                      textAlign: TextAlign.start,
                                      allowUserPause: false,
                                      showTooltip: false,
                                      velocity: 24.0,
                                      blankSpace: 32.0,
                                      style: TextStyle(
                                        color: isPlaying
                                            ? p.accent
                                            : p.textSecondary,
                                        fontSize: 12.0,
                                        fontWeight: isPlaying
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // ── Gilt transport row ─────────────────────────
                              Row(
                                children: [
                                  ExcludeSemantics(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: ctaRadius,
                                        onTap: () => onPlayPressed(isCurrent),
                                        child: Container(
                                          height: 34,
                                          padding:
                                              EdgeInsetsDirectional.fromSTEB(
                                            isPlaying ? 11 : 10,
                                            0,
                                            isPlaying ? 11 : 13,
                                            0,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color.alphaBlend(
                                                  Colors.white
                                                      .withValues(alpha: 0.20),
                                                  gilt,
                                                ),
                                                gilt,
                                              ],
                                            ),
                                            borderRadius: ctaRadius,
                                            boxShadow: [
                                              BoxShadow(
                                                color: gilt.withValues(
                                                  alpha:
                                                      isPlaying ? 0.34 : 0.22,
                                                ),
                                                blurRadius: 10,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                            border: Border.all(
                                              color: onGilt.withValues(
                                                alpha: isPlaying ? 0.32 : 0.16,
                                              ),
                                              width: 0.9,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isBuffering)
                                                SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2.0,
                                                    color: onGilt,
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
                                                Text(
                                                  context.l10n.radioListenNow,
                                                  style: TextStyle(
                                                    color: onGilt,
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.1,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isPlaying) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      height: 34,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: p.accent.withValues(alpha: 0.14),
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
                                          Text(
                                            context.l10n.radioLiveShortBadge,
                                            style: TextStyle(
                                              color: p.accent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
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
                                      ? p.accent.withValues(alpha: 0.78)
                                      : Color.alphaBlend(
                                          gilt.withValues(alpha: 0.20),
                                          p.hairline.withValues(alpha: 0.60),
                                        ),
                                  width: isPlaying ? 1.5 : 1.0,
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

/// Bounded sliding-window indicator: gilt lozenge for the active page,
/// rotated-square diamonds for the rest, faded micro-diamonds at clipped edges.
class _CarouselWindowedDots extends StatelessWidget {
  final int total;
  final int currentPage;
  final ValueChanged<int> onDotTap;

  const _CarouselWindowedDots({
    required this.total,
    required this.currentPage,
    required this.onDotTap,
  });

  static const int _maxVisible = 7;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final gilt = _giltOf(context);
    if (total <= 0) return const SizedBox.shrink();
    final visibleCount = math.min(total, _maxVisible);
    final half = visibleCount ~/ 2;
    final start = total <= _maxVisible
        ? 0
        : (currentPage - half).clamp(0, total - visibleCount);
    final end = start + visibleCount;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = start; i < end; i++)
          Builder(
            builder: (context) {
              final isActive = i == currentPage;
              final isEdgeClipped =
                  (i == start && start > 0) || (i == end - 1 && end < total);
              final dotSize = isEdgeClipped ? 3.5 : 5.5;
              Widget glyph = AnimatedContainer(
                duration: context.motion(PulsrMotion.layout),
                curve: context.motionCurve(PulsrMotion.enter),
                width: isActive ? 20.0 : dotSize,
                height: isActive ? 6.0 : dotSize,
                decoration: BoxDecoration(
                  color: isActive
                      ? gilt
                      : p.textTertiary
                          .withValues(alpha: isEdgeClipped ? 0.22 : 0.36),
                  borderRadius: BorderRadius.circular(isActive ? 3.0 : 1.2),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: gilt.withValues(alpha: 0.40),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
              );
              if (!isActive) {
                glyph = Transform.rotate(angle: math.pi / 4, child: glyph);
              }
              return Semantics(
                button: true,
                label: '${i + 1} / $total',
                child: GestureDetector(
                  onTap: () => onDotTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(0, 6, 4.5, 6),
                    child: glyph,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Pulsing dot indicating live broadcast in theme accent color.
class _PulsingLiveDot extends StatefulWidget {
  const _PulsingLiveDot();

  @override
  State<_PulsingLiveDot> createState() => _PulsingLiveDotState();
}

class _PulsingLiveDotState extends State<_PulsingLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.motionEnabled) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = context.palette.accent;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = 0.5 + (_controller.value * 0.5);
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: dotColor.withValues(alpha: alpha),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: dotColor.withValues(alpha: _controller.value * 0.7),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Mini animated 4-bar equalizer that pulses smoothly when live audio plays.
class _MiniEqualizerBars extends StatefulWidget {
  final bool isPlaying;
  final Color? color;

  const _MiniEqualizerBars({required this.isPlaying, this.color});

  @override
  State<_MiniEqualizerBars> createState() => _MiniEqualizerBarsState();
}

class _MiniEqualizerBarsState extends State<_MiniEqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.isPlaying && context.motionEnabled) {
      if (!_anim.isAnimating) {
        _anim.repeat();
      }
    } else {
      _anim.stop();
      _anim.reset();
    }
  }

  @override
  void didUpdateWidget(covariant _MiniEqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final barColor = widget.color ?? p.accent;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final t = _anim.value * 2 * math.pi;
        final h1 =
            widget.isPlaying ? (5.0 + 7.0 * (0.5 + 0.5 * math.sin(t))) : 4.0;
        final h2 = widget.isPlaying
            ? (5.0 + 9.0 * (0.5 + 0.5 * math.sin(t + 1.2)))
            : 7.0;
        final h3 = widget.isPlaying
            ? (4.0 + 8.0 * (0.5 + 0.5 * math.sin(t + 2.5)))
            : 5.0;
        final h4 = widget.isPlaying
            ? (5.0 + 6.0 * (0.5 + 0.5 * math.sin(t + 3.8)))
            : 6.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildBar(h1, barColor),
            const SizedBox(width: 2.2),
            _buildBar(h2, barColor),
            const SizedBox(width: 2.2),
            _buildBar(h3, barColor),
            const SizedBox(width: 2.2),
            _buildBar(h4, barColor),
          ],
        );
      },
    );
  }

  Widget _buildBar(double height, Color color) {
    return Container(
      width: 2.5,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}
