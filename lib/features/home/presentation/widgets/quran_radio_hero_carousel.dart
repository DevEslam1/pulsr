import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/radio_station_store.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../domain/models/radio_station.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';

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

/// Swipeable Quran Radio Hero Carousel for the HomeScreen.
///
/// Displays curated Quran radio channels starting with Sheikh Mohamed Siddiq
/// El-Minshawi, offering an immersive, tactile audio experience with live
/// transport controls, responsive card scaling, ambient reciter artwork,
/// and smooth page indicators.
class QuranRadioHeroCarousel extends StatefulWidget {
  final PlayerCubit? playerCubit;
  final double height;
  final VoidCallback? onMoreStations;

  const QuranRadioHeroCarousel({
    super.key,
    this.playerCubit,
    this.height = 142.0,
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
          artworkUrl: RadioStationStore.minshawiArtwork,
        ),
        reciterTitleAr: 'الشيخ محمد صديق المنشاوي',
        reciterTitleEn: 'Sheikh Mohamed Siddiq El-Minshawi',
        subtitleAr: 'المصحف المجود • تلاوة خاشعة',
        subtitleEn: 'Holy Quran • Reverent Mujawwad Recitation',
        artworkAsset: RadioStationStore.minshawiArtwork,
        badgeTextAr: 'تلاوة خاشعة',
        badgeTextEn: 'Khashia Recitation',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-khashia',
          name: 'إذاعة تلاوات خاشعة نادرة',
          url: 'https://backup.qurango.net/radio/salma',
          genre: 'Quran',
          artworkUrl: RadioStationStore.tarteelArtwork,
        ),
        reciterTitleAr: 'إذاعة تلاوات خاشعة نادرة',
        reciterTitleEn: 'Rare Khashia Recitations Radio',
        subtitleAr: 'تلاوات خاشعة ومؤثرة • كبار القراء',
        subtitleEn: 'Rare Reverent Recitations • Master Reciters',
        artworkAsset: RadioStationStore.tarteelArtwork,
        badgeTextAr: 'تلاوات خاشعة',
        badgeTextEn: 'Rare Recitations',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-minshawi-rare',
          name: 'إذاعة الشيخ محمد صديق المنشاوي (تلاوات نادرة)',
          url: 'https://radio.xecod.com/station/alminshawi',
          genre: 'Quran',
          artworkUrl: RadioStationStore.minshawiArtwork,
        ),
        reciterTitleAr: 'الشيخ محمد صديق المنشاوي',
        reciterTitleEn: 'Sheikh Mohamed Siddiq El-Minshawi',
        subtitleAr: 'تلاوات نادرة ومحافل خاشعة',
        subtitleEn: 'Rare Historic Recitations & Concerts',
        artworkAsset: RadioStationStore.minshawiArtwork,
        badgeTextAr: 'تلاوات نادرة',
        badgeTextEn: 'Historic Recitations',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-cairo',
          name: 'إذاعة القرآن الكريم المصرية - القاهرة',
          url: 'https://stream.radiojar.com/8s5u5tpdtwzuv',
          genre: 'Quran',
          artworkUrl: RadioStationStore.quranCairoArtwork,
        ),
        reciterTitleAr: 'إذاعة القرآن الكريم - القاهرة',
        reciterTitleEn: 'Holy Quran Radio - Cairo',
        subtitleAr: 'بث مباشر من القاهرة • عبر الأثير',
        subtitleEn: 'Live from Cairo • Over the Air',
        artworkAsset: RadioStationStore.quranCairoArtwork,
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
          artworkUrl: RadioStationStore.abdulBasitArtwork,
        ),
        reciterTitleAr: 'الشيخ عبد الباسط عبد الصمد',
        reciterTitleEn: 'Sheikh Abdulbasit Abdulsamad',
        subtitleAr: 'صوت مكة • المصحف المجود',
        subtitleEn: 'Voice of Mecca • Holy Quran Mujawwad',
        artworkAsset: RadioStationStore.abdulBasitArtwork,
        badgeTextAr: 'المصحف المجود',
        badgeTextEn: 'Mujawwad Mushaf',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-hussary',
          name: 'إذاعة الشيخ محمود خليل الحصري (مرتل)',
          url: 'https://backup.qurango.net/radio/mahmoud_khalil_alhussary',
          genre: 'Quran',
          artworkUrl: RadioStationStore.hussaryArtwork,
        ),
        reciterTitleAr: 'الشيخ محمود خليل الحصري',
        reciterTitleEn: 'Sheikh Mahmoud Khalil Al-Hussary',
        subtitleAr: 'شيخ عموم المقارئ المصرية • المصحف المعلم',
        subtitleEn: 'Master of Reciters • Teaching Mushaf',
        artworkAsset: RadioStationStore.hussaryArtwork,
        badgeTextAr: 'المصحف المعلم',
        badgeTextEn: 'Teacher Mushaf',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-mustafa',
          name: 'إذاعة الشيخ مصطفى إسماعيل (مجود)',
          url: 'https://backup.qurango.net/radio/mustafa_ismail',
          genre: 'Quran',
          artworkUrl: RadioStationStore.mustafaIsmailArtwork,
        ),
        reciterTitleAr: 'الشيخ مصطفى إسماعيل',
        reciterTitleEn: 'Sheikh Mustafa Ismail',
        subtitleAr: 'قارئ الملوك والرؤساء • إعجاز التلاوة',
        subtitleEn: 'Legendary Reciter • Miraculous Recitation',
        artworkAsset: RadioStationStore.mustafaIsmailArtwork,
        badgeTextAr: 'المصحف المجود',
        badgeTextEn: 'Mujawwad Mushaf',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-banna-mojawwad',
          name: 'إذاعة الشيخ محمود علي البنا (مجود)',
          url:
              'https://backup.qurango.net/radio/mahmoud_ali__albanna_mojawwad',
          genre: 'Quran',
          artworkUrl: RadioStationStore.quranCairoArtwork,
        ),
        reciterTitleAr: 'الشيخ محمود علي البنا',
        reciterTitleEn: 'Sheikh Mahmoud Ali Al-Banna',
        subtitleAr: 'المصحف المجود • صوت شجي خاشع',
        subtitleEn: 'Holy Quran Mujawwad • Melodious Voice',
        artworkAsset: RadioStationStore.quranCairoArtwork,
        badgeTextAr: 'المصحف المجود',
        badgeTextEn: 'Mujawwad Mushaf',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-tablaway',
          name: 'إذاعة الشيخ محمد محمود الطبلاوي',
          url: 'https://backup.qurango.net/radio/mohammad_altablaway',
          genre: 'Quran',
          artworkUrl: RadioStationStore.quranCairoArtwork,
        ),
        reciterTitleAr: 'الشيخ محمد محمود الطبلاوي',
        reciterTitleEn: 'Sheikh Mohammad Al-Tablaway',
        subtitleAr: 'تلاوات خاشعة نادرة • نبرة مميزة',
        subtitleEn: 'Rare Recitations • Distinctive Tone',
        artworkAsset: RadioStationStore.quranCairoArtwork,
        badgeTextAr: 'تلاوات خاشعة',
        badgeTextEn: 'Khashia Recitations',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-tarteel',
          name: 'إذاعة تراتيل قصيرة متميزة',
          url: 'https://backup.qurango.net/radio/tarateel',
          genre: 'Quran',
          artworkUrl: RadioStationStore.tarteelArtwork,
        ),
        reciterTitleAr: 'إذاعة تراتيل القرآن الكريم',
        reciterTitleEn: 'Holy Quran Short Recitations Radio',
        subtitleAr: 'تلاوات عذبة مختارة على مدار الساعة',
        subtitleEn: 'Sweet Recitations 24/7',
        artworkAsset: RadioStationStore.tarteelArtwork,
        badgeTextAr: 'تراتيل عذبة',
        badgeTextEn: 'Sweet Tarteel',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-cairo-backup',
          name: 'إذاعة القرآن الكريم - القاهرة (بث بديل)',
          url: 'https://radio.xecod.com/station/quran-cairo',
          genre: 'Quran',
          artworkUrl: RadioStationStore.quranCairoArtwork,
        ),
        reciterTitleAr: 'إذاعة القرآن الكريم - القاهرة',
        reciterTitleEn: 'Holy Quran Radio - Cairo',
        subtitleAr: 'بث بديل عالي الجودة',
        subtitleEn: 'High Quality Backup Stream',
        artworkAsset: RadioStationStore.quranCairoArtwork,
        badgeTextAr: 'بث بديل',
        badgeTextEn: 'Backup Stream',
      ),
    ];
  }

  @override
  State<QuranRadioHeroCarousel> createState() =>
      _QuranRadioHeroCarouselState();
}

class _QuranRadioHeroCarouselState extends State<QuranRadioHeroCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;
  List<QuranHeroItem> _stations = const [];

  @override
  void initState() {
    super.initState();
    final curated = QuranRadioHeroCarousel.defaultQuranStations();
    _stations = curated;
    _pageController = PageController(
      initialPage: 0,
      viewportFraction: 0.93,
    );

    // Merge any custom user stations dynamically
    final store = RadioStationStore();
    store.ready.then((_) {
      if (!mounted) return;
      final storeList = store.list.where(RadioStationStore.isQuranStation);
      final existingUrls = curated.map((c) => c.station.url).toSet();
      final extraItems = <QuranHeroItem>[];
      for (final s in storeList) {
        if (!existingUrls.contains(s.url)) {
          existingUrls.add(s.url);
          final fallbackGenre = s.genre?.isNotEmpty == true ? s.genre! : null;
          extraItems.add(
            QuranHeroItem(
              station: s,
              reciterTitleAr: s.name,
              reciterTitleEn: s.name,
              subtitleAr: fallbackGenre ?? 'إذاعة القرآن الكريم',
              subtitleEn: fallbackGenre ?? 'Holy Quran Radio',
              artworkAsset: s.artworkUrl ?? RadioStationStore.minshawiArtwork,
              badgeTextAr: 'إذاعة مخصصة',
              badgeTextEn: 'Custom Station',
            ),
          );
        }
      }
      if (extraItems.isNotEmpty && mounted) {
        setState(() {
          _stations = [...curated, ...extraItems];
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  PlayerCubit _resolvePlayerCubit(BuildContext context) {
    return widget.playerCubit ?? context.read<PlayerCubit>();
  }

  void _onPlayStation(QuranHeroItem item, bool isCurrent) {
    final playerCubit = _resolvePlayerCubit(context);
    HapticFeedback.mediumImpact();
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
    final total = _stations.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Swipeable Cards Area
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            key: const PageStorageKey('quran_radio_hero_carousel_pv'),
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            itemCount: total,
            onPageChanged: (index) {
              if (index != _currentPage) {
                HapticFeedback.selectionClick();
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
                    value = (page - index).clamp(-1.0, 1.0);
                  } else {
                    value = (_currentPage - index).toDouble().clamp(-1.0, 1.0);
                  }
                  final scale = 1.0 - (value.abs() * 0.04);
                  final opacity = (1.0 - (value.abs() * 0.2)).clamp(0.8, 1.0);

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
                    index: index,
                    total: total,
                    onTap: () {
                      final player = _resolvePlayerCubit(context);
                      final isCurrent =
                          player.state.currentSong?.path == item.station.url;
                      _onPlayStation(item, isCurrent);
                    },
                    onPlayPressed: (isCurrent) =>
                        _onPlayStation(item, isCurrent),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: AppSpacing.s8),

        // Indicator strip: Smooth expanding dot indicator + Quick Radio chip
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0),
          child: Row(
            children: [
              // Pagination Dots
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(total, (i) {
                  final isActive = i == _currentPage;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _pageController.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: Container(
                      margin: const EdgeInsetsDirectional.only(end: 4.5),
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        width: isActive ? 20.0 : 5.5,
                        height: 5.5,
                        decoration: BoxDecoration(
                          color: isActive
                              ? p.accent
                              : p.textTertiary.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(3.0),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: p.accent.withValues(alpha: 0.40),
                                    blurRadius: 6,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  );
                }),
              ),

              const Spacer(),

              // Quick "All Stations" tonal action chip
              Semantics(
                button: true,
                label: 'View all radio stations',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: AppRadii.circular(999),
                    onTap: widget.onMoreStations ??
                        () {
                          HapticFeedback.selectionClick();
                          context.push('/radio');
                        },
                    child: Container(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        8.0,
                        3.0,
                        5.0,
                        3.0,
                      ),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.10),
                        borderRadius: AppRadii.circular(999),
                        border: Border.all(
                          color: p.accent.withValues(alpha: 0.24),
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
                          const SizedBox(width: 4),
                          Text(
                            context.l10n.radioTitle,
                            style: TextStyle(
                              color: p.accent,
                              fontSize: AppFontSize.tiny,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.25,
                            ),
                          ),
                          const SizedBox(width: 1),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: p.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The individual stylized hero card for a single Quran station.
class _QuranHeroCard extends StatelessWidget {
  final QuranHeroItem item;
  final int index;
  final int total;
  final VoidCallback onTap;
  final void Function(bool isCurrent) onPlayPressed;

  const _QuranHeroCard({
    required this.item,
    required this.index,
    required this.total,
    required this.onTap,
    required this.onPlayPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

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
        final rawIcyTitle = isCurrent
            ? (playerState.currentSong?.album.trim() ?? '')
            : '';
        final defaultSubtitle = item.getSubtitle(isArabic);
        final displaySubtitle =
            rawIcyTitle.isNotEmpty ? rawIcyTitle : defaultSubtitle;
        final reciterTitle = item.getReciterTitle(isArabic);
        final badgeText = item.getBadgeText(isArabic);
        final defaultBadge =
            isArabic ? 'إذاعة القرآن الكريم' : 'Holy Quran Radio';

        final baseSurface = p.surfaceContainer;
        final elevatedSurface = Color.alphaBlend(
          (isPlaying ? AppColors.mint : p.accent)
              .withValues(alpha: p.isDark ? 0.10 : 0.06),
          p.surfaceContainerHigh,
        );

        return Semantics(
          button: true,
          label:
              '$reciterTitle, $displaySubtitle. ${isPlaying ? (isArabic ? "قيد التشغيل، اضغط للإيقاف" : "Playing, double tap to pause") : (isArabic ? "اضغط للتشغيل" : "Double tap to play live stream")}',
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadii.r24All,
            child: InkWell(
              borderRadius: AppRadii.r24All,
              onTap: onTap,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [
                      elevatedSurface,
                      baseSurface,
                    ],
                  ),
                  borderRadius: AppRadii.r24All,
                  border: Border.all(
                    color: isPlaying
                        ? p.accent.withValues(alpha: 0.70)
                        : p.accent.withValues(alpha: 0.24),
                    width: isPlaying ? 1.5 : 1.0,
                  ),
                  boxShadow: isPlaying
                      ? [
                          BoxShadow(
                            color: p.accent.withValues(alpha: 0.22),
                            blurRadius: 22,
                            spreadRadius: -2,
                            offset: const Offset(0, 6),
                          ),
                          ...PulsrElevation.level2(context),
                        ]
                      : PulsrElevation.level2(context),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Ambient radial glow behind the reciter portrait stage
                    PositionedDirectional(
                      end: -20,
                      top: -20,
                      bottom: -20,
                      width: 170,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                p.accent.withValues(
                                    alpha: isPlaying ? 0.22 : 0.12),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Reciter Ambient Artwork (Trailing alignment - unobstructed stage)
                    PositionedDirectional(
                      end: 0,
                      top: 0,
                      bottom: 0,
                      width: 148,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isNetwork =
                              item.artworkAsset.startsWith('http://') ||
                                  item.artworkAsset.startsWith('https://');

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              if (isNetwork)
                                CachedArtwork(
                                  id: 0,
                                  remoteUrl: item.artworkAsset,
                                  size: 148,
                                  fallbackIcon: Icons.radio_rounded,
                                )
                              else
                                Image.asset(
                                  item.artworkAsset,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.topCenter,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: p.accentContainer
                                        .withValues(alpha: 0.2),
                                    child: Icon(
                                      Icons.radio_rounded,
                                      size: 48,
                                      color: p.accent.withValues(alpha: 0.3),
                                    ),
                                  ),
                                ),
                              // Smooth multi-stop fade from card surface into the portrait
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: AlignmentDirectional.centerStart,
                                    end: AlignmentDirectional.centerEnd,
                                    colors: [
                                      baseSurface,
                                      baseSurface.withValues(alpha: 0.86),
                                      baseSurface.withValues(alpha: 0.28),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.32, 0.68, 1.0],
                                  ),
                                ),
                              ),
                              // Subtle vertical vignette for contrast in light & dark modes
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.08),
                                      Colors.black.withValues(alpha: 0.38),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    // Top inner specular highlight hairline
                    Positioned(
                      top: 0,
                      left: 24,
                      right: 24,
                      child: IgnorePointer(
                        child: Container(
                          height: 1,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.0),
                                (p.isDark ? Colors.white : Colors.black)
                                    .withValues(alpha: p.isDark ? 0.14 : 0.05),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Decorative background Islamic/Quran waveform watermark
                    PositionedDirectional(
                      start: -12,
                      bottom: -16,
                      child: ExcludeSemantics(
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          size: 100,
                          color: p.accent
                              .withValues(alpha: isPlaying ? 0.08 : 0.045),
                        ),
                      ),
                    ),

                    // Foreground Content Layer (Leaves trailing side open for portrait)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.md,
                        10,
                        125,
                        10,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Overline: Status / Reciter Pill Badge + Counter Chip
                          Row(
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPlaying
                                        ? AppColors.mint.withValues(alpha: 0.18)
                                        : p.accent.withValues(alpha: 0.14),
                                    borderRadius: AppRadii.circular(999),
                                    border: Border.all(
                                      color: isPlaying
                                          ? AppColors.mint
                                              .withValues(alpha: 0.45)
                                          : p.accent.withValues(alpha: 0.30),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isPlaying) ...[
                                        const _PulsingLiveDot(),
                                        const SizedBox(width: 4.5),
                                        Flexible(
                                          child: Text(
                                            isArabic
                                                ? 'بث مباشر'
                                                : 'LIVE ON AIR',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: AppColors.mint,
                                              fontSize: AppFontSize.tiny,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ] else ...[
                                        Icon(
                                          Icons.radio_rounded,
                                          size: 11,
                                          color: p.accent,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            badgeText ?? defaultBadge,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: p.accent,
                                              fontSize: AppFontSize.tiny,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Station count micro-pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5.5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: p.surfaceContainerHighest
                                      .withValues(alpha: 0.65),
                                  borderRadius: AppRadii.r6All,
                                  border: Border.all(
                                    color: p.hairline.withValues(alpha: 0.6),
                                    width: 0.6,
                                  ),
                                ),
                                child: Text(
                                  '${index + 1}/$total',
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.tiny,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 5),

                          // Station/Reciter Title
                          MarqueeText(
                            text: reciterTitle,
                            textAlign: TextAlign.start,
                            allowUserPause: false,
                            velocity: 28.0,
                            blankSpace: 36.0,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.2,
                            ),
                          ),

                          const SizedBox(height: 2),

                          // Subtitle / Live ICY surah info
                          Row(
                            children: [
                              if (isPlaying)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                      end: 4.0),
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
                                  velocity: 24.0,
                                  blankSpace: 32.0,
                                  style: TextStyle(
                                    color:
                                        isPlaying ? p.accent : p.textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: isPlaying
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Bottom Action Row: Tactile Play/Pause Button + Status Capsule
                          Row(
                            children: [
                              ExcludeSemantics(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: AppRadii.circular(999),
                                    onTap: () => onPlayPressed(isCurrent),
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color.alphaBlend(
                                              Colors.white
                                                  .withValues(alpha: 0.16),
                                              p.accent,
                                            ),
                                            p.accent,
                                          ],
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          ...PulsrElevation.level2(context),
                                          BoxShadow(
                                            color: p.accent.withValues(
                                              alpha: isPlaying ? 0.34 : 0.18,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                        border: Border.all(
                                          color: p.onAccent.withValues(
                                            alpha: isPlaying ? 0.38 : 0.18,
                                          ),
                                          width: isPlaying ? 1.5 : 1.0,
                                        ),
                                      ),
                                      child: Center(
                                        child: isBuffering
                                            ? SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.0,
                                                  color: p.onAccent,
                                                ),
                                              )
                                            : Icon(
                                                isPlaying
                                                    ? Icons.pause_rounded
                                                    : Icons.play_arrow_rounded,
                                                color: p.onAccent,
                                                size: isPlaying ? 22 : 25,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.5,
                                  vertical: 4.5,
                                ),
                                decoration: BoxDecoration(
                                  color: isPlaying
                                      ? AppColors.mint.withValues(alpha: 0.12)
                                      : p.surfaceContainerHighest
                                          .withValues(alpha: 0.55),
                                  borderRadius: AppRadii.circular(999),
                                  border: Border.all(
                                    color: isPlaying
                                        ? AppColors.mint.withValues(alpha: 0.30)
                                        : p.hairline.withValues(alpha: 0.65),
                                    width: 0.75,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isPlaying) ...[
                                      _MiniEqualizerBars(
                                        isPlaying: true,
                                        color: AppColors.mint,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isArabic ? 'بث حي' : 'LIVE',
                                        style: TextStyle(
                                          color: AppColors.mint,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ] else ...[
                                      Icon(
                                        Icons.volume_up_rounded,
                                        size: 13,
                                        color: p.textSecondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isArabic ? 'استمع الآن' : 'Listen Now',
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pulsing green dot indicating live broadcast.
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
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = 0.5 + (_controller.value * 0.5);
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: AppColors.mint.withValues(alpha: alpha),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.mint
                    .withValues(alpha: _controller.value * 0.7),
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
    if (widget.isPlaying) _anim.repeat();
  }

  @override
  void didUpdateWidget(covariant _MiniEqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _anim.repeat();
      } else {
        _anim.stop();
        _anim.reset();
      }
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