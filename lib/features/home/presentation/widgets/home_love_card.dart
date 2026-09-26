// lib/features/home/presentation/widgets/home_love_card.dart
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';

/// Interactive frosted glass card featuring 100 dynamic love messages customized
/// for Dr. Basbosa that rotate on every visit or tap, with smooth animated transitions,
/// ambient breathing glow, responsive adaptive sizing, and burst waves of floating love emojis!
class HomeLoveCard extends StatefulWidget {
  const HomeLoveCard({super.key});

  @override
  State<HomeLoveCard> createState() => _HomeLoveCardState();
}

class _HomeLoveCardState extends State<HomeLoveCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  // 100 sweet, heartfelt love messages for Dr. Basbosa
  static final List<String> _loveQuotes = [
    // 1 - 10
    '"You make every beat worthwhile. Enjoy your music, my love!"',
    '"To the world you may be one person, but to me you are the whole world, Dr. Basbosa 💕"',
    '"Every melody sounds sweeter when I think of you ✨"',
    '"You are my favorite song playing on repeat in my heart forever 🎶"',
    '"No symphony in this world compares to your voice and your smile 💖"',
    '"Forever blessed and proud of my brilliant, beautiful Dr. Basbosa 🌟"',
    '"My heart skips a beat every time your name comes to my mind 💓"',
    '"In every lifetime, in every universe, it will always be you ❤️"',
    '"You are the sweetest rhythm in this journey of life 🌸"',
    '"May your day be as gentle, bright, and radiant as your soul ✨"',

    // 11 - 20
    '"Falling in love with you is the easiest and most wonderful thing I ever did 🌹"',
    '"Your laughter is the soundtrack that cures all my worries 🎵"',
    '"You are my sunshine on cloudy days and my sweetest dream every night 🌙"',
    '"Dr. Basbosa: saving lives by day, owning my heart 24/7 🩺❤️"',
    '"The smartest doctor, the prettiest soul, and the love of my life 🥰"',
    '"I loved you yesterday, I love you still, I always have, I always will 💍"',
    '"No artist could ever paint a masterpiece as breathtaking as you 🎨"',
    '"Every second spent loving you is my favorite second of the day ⏳💕"',
    '"You make ordinary moments feel like pure fairy tales ✨"',
    '"Wherever you go, my heart follows your footsteps 👣💖"',

    // 21 - 30
    '"Your kindness inspires me to be the very best version of myself 🕊️"',
    '"Holding your hand feels like holding my entire future 🤝❤️"',
    '"The universe conspired to bring you into my life, and I am eternally grateful 🌌"',
    '"You are my peaceful oasis in this noisy, chaotic world 🏝️✨"',
    '"One smile from you lights up even the darkest room in an instant 💡🌸"',
    '"Dr. Basbosa, you are both my greatest adventure and my safest home 🏡❤️"',
    '"Every love song suddenly makes total sense whenever I look at you 🎼"',
    '"You have the kindest eyes and the most gentle, loving touch 👁️💕"',
    '"My heart belongs to you today, tomorrow, and for all eternity ♾️"',
    '"Being loved by you is the greatest privilege of my lifetime 👑"',

    // 31 - 40
    '"You are my favorite person to laugh with, dream with, and love forever 💭💗"',
    '"If I had a flower for every time I thought of you, I could walk through an endless garden 🌷"',
    '"Thank you for filling my life with endless warmth, laughter, and joy ☀️"',
    '"You are the missing piece that made my whole world complete 🧩💖"',
    '"Your intelligence amazes me, your heart humbles me, and your love heals me 🩺✨"',
    '"I promise to always stand by your side, cheering you on through everything 📣❤️"',
    '"Even on the busiest days, my mind always finds its way back to you 🧭💕"',
    '"You are proof that magic, elegance, and pure grace truly exist 🪄✨"',
    '"My favorite place in the whole wide world is right next to you 🌍❤️"',
    '"You make my soul dance with joy every single morning 💃🎶"',

    // 41 - 50
    '"God truly blessed me when our paths crossed, Dr. Basbosa 🙏💖"',
    '"You bring melody to my silence and light into my shadows 🕯️✨"',
    '"The sweetest doctor in the world deserves the sweetest day every single day 🍬🩺"',
    '"You are more precious to me than all the treasures on this earth 💎"',
    '"Nothing feels impossible when I have your love cheering me on 🚀❤️"',
    '"You make life sweeter than honey and softer than cotton candy 🍯💕"',
    '"A single text from you still gives me the biggest butterflies in my stomach 🦋"',
    '"You are the reason behind every genuine smile on my face 😊💖"',
    '"Your heart is made of pure gold, and I will cherish it forever 💛"',
    '"I would choose you over and over again, in a thousand lifetimes 🔄❤️"',

    // 51 - 60
    '"May your patients be healed, your exams be easy, and your heart be full of joy 🩺🌟"',
    '"You are my favorite notification and my favorite thought 📱💕"',
    '"Just listening to music and picturing your smile makes everything okay 🎧✨"',
    '"You are the sweetest dream I never want to wake up from 🛌💭"',
    '"No matter how far apart we are, our hearts beat in perfect sync 💓📡"',
    '"You are the rhythm to my pulse and the bass in my chest 🥁❤️"',
    '"Your hugs feel like wrapped-up warmth and ultimate comfort 🫂🧸"',
    '"I am endlessly proud of everything you are achieving, my brilliant doctor 🏆🩺"',
    '"With you, every day feels like Valentine\'s Day 💌🌹"',
    '"You are the miracle I prayed for, and the love I always dreamed of 🌈💕"',

    // 61 - 70
    '"I love the way your eyes sparkle when you talk about your passions ✨👁️"',
    '"You are my anchor when the storm gets rough, and my wings when I fly ⚓🕊️"',
    '"Every love story is beautiful, but ours is by far my favorite 📖❤️"',
    '"You turned my life into a love song that never ends 🎻🎶"',
    '"If kisses were snowflakes, I would send you a never-ending winter blizzard ❄️💋"',
    '"My favorite feeling is knowing that you are mine and I am yours 🔐💖"',
    '"You make my world infinitely brighter just by being in it 🌟🌍"',
    '"I love your strength, your gentle tenderness, and your gorgeous spirit 🌸"',
    '"Dr. Basbosa, you make curing hearts look effortless 🥰🩺"',
    '"You are the melody that makes my soul sing along every day 🎤💖"',

    // 71 - 80
    '"There are billions of people on Earth, but only one Dr. Basbosa for me 🪐❤️"',
    '"Your sweet voice is my favorite sound to wake up to 🌅🎶"',
    '"I will love you through every season, every storm, and every celebration 🍂🌸"',
    '"You are my today and all of my tomorrows 🗓️💕"',
    '"Thank you for being my rock, my lover, and my dearest best friend 🤝❤️"',
    '"When I close my eyes, I see your smile, and suddenly everything is peaceful 😌✨"',
    '"I don\'t need the stars when I have the radiance of your eyes 🌌👁️"',
    '"Everything I do is inspired by the hope of making you smile proudly 🎯💖"',
    '"You are sweeter than basbosa and more precious than rubies 🍯💎"',
    '"Loving you is as natural and vital to me as breathing oxygen 🫁❤️"',

    // 81 - 90
    '"May angels watch over you and keep your gentle heart safe always 👼💕"',
    '"You deserve all the love, all the roses, and all the happiness in the world 🌹💐"',
    '"My heart is forever tuned to your frequency 📻💖"',
    '"You are my good morning, my good night, and every lovely thought in between 🌇🌃"',
    '"With every passing day, I discover a hundred new reasons to adore you 📈❤️"',
    '"You are the finest melody God ever composed in this universe 🎹✨"',
    '"I can conquer the entire world with one hand, as long as you are holding the other 🛡️🤝"',
    '"Your love is the sweet warmth that keeps my spirit cozy all winter long ☕🧣"',
    '"I thank the stars above every single night for blessing me with you 🌠🙏"',
    '"You are the cure to all fatigue and the spark in my everyday life ⚡💕"',

    // 91 - 100
    '"Dr. Basbosa, you make every heartbeat sound like poetry 🩺📜"',
    '"Never forget how deeply, truly, and uncontrollably loved you are 🌊❤️"',
    '"You are the song stuck in my head that I never want to turn off 🔁🎶"',
    '"My favorite view is looking right into your joyful, smiling eyes 🖼️🥰"',
    '"You and me against the world, always and forever 🏰❤️"',
    '"I love you more than words, code, music, and poetry could ever explain 💻🎵"',
    '"You are my paradise, my sanctuary, and my peace 🕊️🌸"',
    '"Whatever tomorrow brings, I know it\'s bright because you\'re in it 🌅💖"',
    '"Forever cheering for my doctor, my angel, my queen, Dr. Basbosa 👑🩺"',
    '"Eng. Eslam loves Dr. Basbosa to infinity, beyond the galaxies, and back! 🚀🌌💖✨"',
  ];

  static int _lastIndex = -1;
  late int _currentIndex;
  bool _loved = false;

  // Floating love particle waves
  final List<_LoveParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    // Pick a new random quote each time the screen/card mounts
    int nextIndex;
    if (_loveQuotes.length > 1) {
      do {
        nextIndex = _random.nextInt(_loveQuotes.length);
      } while (nextIndex == _lastIndex);
    } else {
      nextIndex = 0;
    }
    _lastIndex = nextIndex;
    _currentIndex = nextIndex;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    _glowAnimation = Tween<double>(begin: 0.20, end: 0.55).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _triggerEmojiWave(TapUpDetails details, Size cardSize) {
    HapticFeedback.mediumImpact();
    final emojis = ['💖', '💕', '✨', '❤️', '🩺', '🌸', '💓', '🌟', '🥰', '💌'];
    final tapOffset = details.localPosition;

    // Generate burst wave of 14 particles from tap location
    for (int i = 0; i < 14; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 70.0 + _random.nextDouble() * 120.0;
      final emoji = emojis[_random.nextInt(emojis.length)];
      final particle = _LoveParticle(
        id: UniqueKey().toString(),
        emoji: emoji,
        origin: tapOffset,
        velocity: Offset(cos(angle) * speed, sin(angle) * speed - 60.0),
        size: 16.0 + _random.nextDouble() * 14.0,
      );

      _particles.add(particle);
    }

    setState(() {
      _currentIndex = (_currentIndex + 1) % _loveQuotes.length;
      _lastIndex = _currentIndex;
      _loved = true;
    });
  }

  void _onParticleTick(String id) {
    setState(() {
      _particles.removeWhere((p) => p.id == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 360;

    // Adaptive sizing
    final cardPaddingH = isTablet ? 20.0 : (isCompact ? 12.0 : 16.0);
    final cardPaddingV = isTablet ? 18.0 : (isCompact ? 11.0 : 14.0);
    final heartSize = isTablet ? 24.0 : (isCompact ? 18.0 : 21.0);
    final quoteFontSize = isTablet ? 14.0 : (isCompact ? 11.5 : 12.8);

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(top: 14, bottom: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2A85)
                    .withValues(alpha: _glowAnimation.value),
                blurRadius: 28,
                spreadRadius: -2,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFFFF2A85).withValues(alpha: 0.28),
                              const Color(0xFF320822).withValues(alpha: 0.65),
                              const Color(0xFF14020F).withValues(alpha: 0.85),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFFFF2A85)
                                .withValues(alpha: 0.42),
                            width: 1.4,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTapUp: (details) => _triggerEmojiWave(
                              details,
                              Size(constraints.maxWidth, 120),
                            ),
                            splashColor: const Color(0xFFFF2A85)
                                .withValues(alpha: 0.25),
                            highlightColor: Colors.transparent,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: cardPaddingH,
                                vertical: cardPaddingV,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Pulsing Neon Heart with Glow halo
                                  ScaleTransition(
                                    scale: _scaleAnimation,
                                    child: Container(
                                      padding: EdgeInsets.all(isCompact ? 9 : 11),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFFFF2A85),
                                            Color(0xFFBA085B),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFF2A85)
                                                .withValues(alpha: 0.65),
                                            blurRadius: 16,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        _loved
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_rounded,
                                        color: Colors.white,
                                        size: heartSize,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: isCompact ? 10 : 15),

                                  // Text with AnimatedSwitcher for smooth message cross-fade & slide
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'MELODY OF MY HEART',
                                              style: TextStyle(
                                                color: const Color(0xFFFF85BC),
                                                fontSize: isCompact ? 8.5 : 10,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 1.2,
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: isCompact ? 6 : 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFF2A85)
                                                    .withValues(alpha: 0.25),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: const Color(0xFFFF2A85)
                                                      .withValues(alpha: 0.40),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.auto_awesome_rounded,
                                                    size: isCompact ? 9 : 10,
                                                    color: const Color(0xFFFF85BC),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Dr. Basbosa 💕',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize:
                                                          isCompact ? 9.5 : 10.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),

                                        // Animated quote message
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                              milliseconds: 350),
                                          switchInCurve: Curves.easeOutCubic,
                                          switchOutCurve: Curves.easeInCubic,
                                          transitionBuilder:
                                              (child, animation) {
                                            return FadeTransition(
                                              opacity: animation,
                                              child: SlideTransition(
                                                position: Tween<Offset>(
                                                  begin:
                                                      const Offset(0.0, 0.15),
                                                  end: Offset.zero,
                                                ).animate(animation),
                                                child: child,
                                              ),
                                            );
                                          },
                                          child: Text(
                                            _loveQuotes[_currentIndex],
                                            key: ValueKey<int>(_currentIndex),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: quoteFontSize,
                                              fontWeight: FontWeight.w600,
                                              fontStyle: FontStyle.italic,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),

                                        const SizedBox(height: 5),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '— Eng. Eslam ✨',
                                              style: TextStyle(
                                                color: const Color(0xFFFF85BC),
                                                fontSize: isCompact ? 9.5 : 11,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.4,
                                              ),
                                            ),
                                            Text(
                                              'Tap for wave of love 💌',
                                              style: TextStyle(
                                                color: p.textTertiary
                                                    .withValues(alpha: 0.70),
                                                fontSize:
                                                    isCompact ? 8.5 : 9.5,
                                                fontWeight: FontWeight.w600,
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
                      ),

                      // Floating Animated Emoji Waves
                      for (final particle in _particles)
                        _AnimatedFloatingEmoji(
                          key: ValueKey(particle.id),
                          particle: particle,
                          onCompleted: () => _onParticleTick(particle.id),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LoveParticle {
  final String id;
  final String emoji;
  final Offset origin;
  final Offset velocity;
  final double size;

  _LoveParticle({
    required this.id,
    required this.emoji,
    required this.origin,
    required this.velocity,
    required this.size,
  });
}

class _AnimatedFloatingEmoji extends StatefulWidget {
  final _LoveParticle particle;
  final VoidCallback onCompleted;

  const _AnimatedFloatingEmoji({
    super.key,
    required this.particle,
    required this.onCompleted,
  });

  @override
  State<_AnimatedFloatingEmoji> createState() => _AnimatedFloatingEmojiState();
}

class _AnimatedFloatingEmojiState extends State<_AnimatedFloatingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..forward().then((_) => widget.onCompleted());
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final t = _anim.value;
        // Float outward and upward with slight gravity deceleration
        final dx = widget.particle.origin.dx +
            widget.particle.velocity.dx * (t * 0.9);
        final dy = widget.particle.origin.dy +
            widget.particle.velocity.dy * t +
            (40.0 * t * t);

        final opacity = (1.0 - t).clamp(0.0, 1.0);
        final scale = (0.5 + t * 0.8).clamp(0.0, 1.4);

        return Positioned(
          left: dx - (widget.particle.size / 2),
          top: dy - (widget.particle.size / 2),
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Text(
                  widget.particle.emoji,
                  style: TextStyle(
                    fontSize: widget.particle.size,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
