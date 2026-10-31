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
  final String reciterTitle;
  final String subtitle;
  final String artworkAsset;
  final String? badgeText;

  const QuranHeroItem({
    required this.station,
    required this.reciterTitle,
    required this.subtitle,
    required this.artworkAsset,
    this.badgeText,
  });
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
        reciterTitle: 'الشيخ محمد صديق المنشاوي',
        subtitle: 'المصحف المجود • تلاوة خاشعة',
        artworkAsset: RadioStationStore.minshawiArtwork,
        badgeText: 'تلاوة خاشعة',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-khashia',
          name: 'إذاعة تلاوات خاشعة نادرة',
          url: 'https://backup.qurango.net/radio/salma',
          genre: 'Quran',
          artworkUrl: RadioStationStore.tarteelArtwork,
        ),
        reciterTitle: 'إذاعة تلاوات خاشعة نادرة',
        subtitle: 'تلاوات خاشعة ومؤثرة • كبار القراء',
        artworkAsset: RadioStationStore.tarteelArtwork,
        badgeText: 'تلاوات خاشعة',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-minshawi-rare',
          name: 'إذاعة الشيخ محمد صديق المنشاوي (تلاوات نادرة)',
          url: 'https://radio.xecod.com/station/alminshawi',
          genre: 'Quran',
          artworkUrl: RadioStationStore.minshawiArtwork,
        ),
        reciterTitle: 'الشيخ محمد صديق المنشاوي',
        subtitle: 'تلاوات نادرة ومحافل خاشعة',
        artworkAsset: RadioStationStore.minshawiArtwork,
        badgeText: 'تلاوات نادرة',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-cairo',
          name: 'إذاعة القرآن الكريم المصرية - القاهرة',
          url: 'https://stream.radiojar.com/8s5u5tpdtwzuv',
          genre: 'Quran',
          artworkUrl: RadioStationStore.quranCairoArtwork,
        ),
        reciterTitle: 'إذاعة القرآن الكريم - القاهرة',
        subtitle: 'بث مباشر من القاهرة • عبر الأثير',
        artworkAsset: RadioStationStore.quranCairoArtwork,
        badgeText: 'بث مباشر',
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
        reciterTitle: 'الشيخ عبد الباسط عبد الصمد',
        subtitle: 'صوت مكة • المصحف المجود',
        artworkAsset: RadioStationStore.abdulBasitArtwork,
        badgeText: 'المصحف المجود',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-hussary',
          name: 'إذاعة الشيخ محمود خليل الحصري (مرتل)',
          url: 'https://backup.qurango.net/radio/mahmoud_khalil_alhussary',
          genre: 'Quran',
          artworkUrl: RadioStationStore.hussaryArtwork,
        ),
        reciterTitle: 'الشيخ محمود خليل الحصري',
        subtitle: 'شيخ عموم المقارئ المصرية • المصحف المعلم',
        artworkAsset: RadioStationStore.hussaryArtwork,
        badgeText: 'المصحف المعلم',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-mustafa',
          name: 'إذاعة الشيخ مصطفى إسماعيل (مجود)',
          url: 'https://backup.qurango.net/radio/mustafa_ismail',
          genre: 'Quran',
          artworkUrl: RadioStationStore.mustafaIsmailArtwork,
        ),
        reciterTitle: 'الشيخ مصطفى إسماعيل',
        subtitle: 'قارئ الملوك والرؤساء • إعجاز التلاوة',
        artworkAsset: RadioStationStore.mustafaIsmailArtwork,
        badgeText: 'المصحف المجود',
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
        reciterTitle: 'الشيخ محمود علي البنا',
        subtitle: 'المصحف المجود • صوت شجي خاشع',
        artworkAsset: RadioStationStore.quranCairoArtwork,
        badgeText: 'المصحف المجود',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-tablaway',
          name: 'إذاعة الشيخ محمد محمود الطبلاوي',
          url: 'https://backup.qurango.net/radio/mohammad_altablaway',
          genre: 'Quran',
          artworkUrl: RadioStationStore.quranCairoArtwork,
        ),
        reciterTitle: 'الشيخ محمد محمود الطبلاوي',
        subtitle: 'تلاوات خاشعة نادرة • نبرة مميزة',
        artworkAsset: RadioStationStore.quranCairoArtwork,
        badgeText: 'تلاوات خاشعة',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-tarteel',
          name: 'إذاعة تراتيل قصيرة متميزة',
          url: 'https://backup.qurango.net/radio/tarateel',
          genre: 'Quran',
          artworkUrl: RadioStationStore.tarteelArtwork,
        ),
        reciterTitle: 'إذاعة تراتيل القرآن الكريم',
        subtitle: 'تلاوات عذبة مختارة على مدار الساعة',
        artworkAsset: RadioStationStore.tarteelArtwork,
        badgeText: 'تراتيل عذبة',
      ),
      const QuranHeroItem(
        station: RadioStation(
          id: 'cur-quran-cairo-backup',
          name: 'إذاعة القرآن الكريم - القاهرة (بث بديل)',
          url: 'https://radio.xecod.com/station/quran-cairo',
          genre: 'Quran',
          artworkUrl: RadioStationStore.quranCairoArtwork,
        ),
        reciterTitle: 'إذاعة القرآن الكريم - القاهرة',
        subtitle: 'بث بديل عالي الجودة',
        artworkAsset: RadioStationStore.quranCairoArtwork,
        badgeText: 'بث بديل',
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
          extraItems.add(
            QuranHeroItem(
              station: s,
              reciterTitle: s.name,
              subtitle: s.genre ?? 'إذاعة القرآن الكريم',
              artworkAsset: s.artworkUrl ?? RadioStationStore.minshawiArtwork,
              badgeText: 'إذاعة مخصصة',
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
      playerCubit.playRadioStation(item.station);
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

        // Indicator strip: Smooth expanding dot indicator + Quick Radio link
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            children: [
              // Dots
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
                      margin: const EdgeInsetsDirectional.only(end: 4.0),
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        width: isActive ? 18.0 : 5.0,
                        height: 5.0,
                        decoration: BoxDecoration(
                          color: isActive
                              ? p.accent
                              : p.textTertiary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                  );
                }),
              ),

              const Spacer(),

              // Quick "All Stations" action
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6.0,
                        vertical: 2.0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.radio_rounded,
                            size: 13,
                            color: p.accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            context.l10n.radioTitle,
                            style: TextStyle(
                              color: p.accent,
                              fontSize: AppFontSize.tiny,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 2),
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
        final isCurrent = playerState.currentSong?.path == item.station.url;
        final isPlaying = isCurrent && playerState.isPlaying;
        final isBuffering = isCurrent && playerState.isBuffering;
        final rawIcyTitle = isCurrent
            ? (playerState.currentSong?.album.trim() ?? '')
            : '';
        final displaySubtitle =
            rawIcyTitle.isNotEmpty ? rawIcyTitle : item.subtitle;

        return Semantics(
          button: true,
          label:
              '${item.reciterTitle}, ${item.subtitle}. ${isPlaying ? "Playing, double tap to pause" : "Double tap to play live stream"}',
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadii.r24All,
            child: InkWell(
              borderRadius: AppRadii.r24All,
              onTap: onTap,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: AppRadii.r24All,
                  border: Border.all(
                    color: isPlaying
                        ? p.accent.withValues(alpha: 0.65)
                        : p.accent.withValues(alpha: 0.22),
                    width: isPlaying ? 1.5 : 1.0,
                  ),
                  boxShadow: isPlaying
                      ? [
                          BoxShadow(
                            color: p.accent.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                          ...PulsrElevation.level2(context),
                        ]
                      : PulsrElevation.level2(context),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Reciter Ambient Artwork (Trailing alignment - unobstructed stage)
                    PositionedDirectional(
                      end: 0,
                      top: 0,
                      bottom: 0,
                      width: 145,
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
                                  size: 145,
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
                              // Smooth fade from surfaceContainer into the photo
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: AlignmentDirectional.centerStart,
                                    end: AlignmentDirectional.centerEnd,
                                    colors: [
                                      p.surfaceContainer,
                                      p.surfaceContainer.withValues(alpha: 0.8),
                                      p.surfaceContainer.withValues(alpha: 0.15),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.35, 0.75, 1.0],
                                  ),
                                ),
                              ),
                              // Subtle vignette darkening for high contrast in light & dark modes
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.1),
                                      Colors.black.withValues(alpha: 0.35),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
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
                          color: p.accent.withValues(alpha: 0.05),
                        ),
                      ),
                    ),

                    // Foreground Content Layer (Leaves right side open for portrait)
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
                          // Top Overline: Status / Reciter Pill Badge
                          Row(
                            children: [
                              Container(
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
                                        ? AppColors.mint.withValues(alpha: 0.4)
                                        : p.accent.withValues(alpha: 0.28),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isPlaying) ...[
                                      const _PulsingLiveDot(),
                                      const SizedBox(width: 4),
                                      Text(
                                        'بث مباشر',
                                        style: TextStyle(
                                          color: AppColors.mint,
                                          fontSize: AppFontSize.tiny,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ] else ...[
                                      Icon(
                                        Icons.radio_rounded,
                                        size: 11,
                                        color: p.accent,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        item.badgeText ?? 'إذاعة القرآن الكريم',
                                        style: TextStyle(
                                          color: p.accent,
                                          fontSize: AppFontSize.tiny,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Station count badge
                              Text(
                                '${index + 1}/$total',
                                style: TextStyle(
                                  color: p.textTertiary,
                                  fontSize: AppFontSize.tiny,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 5),

                          // Station/Reciter Title
                          MarqueeText(
                            text: item.reciterTitle,
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
                                    color: isPlaying
                                        ? p.accent
                                        : p.textSecondary,
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

                          // Bottom Action Row: Play/Pause Button + Equalizer / Hint
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
                                        color: p.accent,
                                        shape: BoxShape.circle,
                                        boxShadow:
                                            PulsrElevation.level2(context),
                                        border: isPlaying
                                            ? Border.all(
                                                color: p.onAccent
                                                    .withValues(alpha: 0.35),
                                                width: 1.5,
                                              )
                                            : null,
                                      ),
                                      child: Center(
                                        child: isBuffering
                                            ? SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
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
                              if (isPlaying) ...[
                                _MiniEqualizerBars(
                                  isPlaying: true,
                                  color: AppColors.mint,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'بث حي',
                                  style: TextStyle(
                                    color: AppColors.mint,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ] else ...[
                                Icon(
                                  Icons.volume_up_rounded,
                                  size: 13,
                                  color: p.textTertiary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'استمع الآن',
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
