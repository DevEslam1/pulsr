// lib/features/home/presentation/widgets/home_love_card.dart
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/aura_theme.dart';

/// Interactive frosted glass card featuring dynamic love messages that rotate
/// on every visit or tap, with smooth animated transitions, ambient glow,
/// and haptic feedback.
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

  static final List<String> _loveQuotes = [
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
  ];

  static int _lastIndex = -1;
  late int _currentIndex;
  bool _loved = false;

  @override
  void initState() {
    super.initState();

    // Pick a new random quote each time the screen/card mounts
    final random = Random();
    int nextIndex;
    if (_loveQuotes.length > 1) {
      do {
        nextIndex = random.nextInt(_loveQuotes.length);
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

  void _cycleMessage() {
    HapticFeedback.lightImpact();
    setState(() {
      _currentIndex = (_currentIndex + 1) % _loveQuotes.length;
      _lastIndex = _currentIndex;
      _loved = true;
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Eng. Eslam loves Dr. Basbosa to infinity & beyond! 💖✨',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFF2A85),
        duration: const Duration(milliseconds: 2500),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(top: 14, bottom: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2A85).withValues(alpha: _glowAnimation.value),
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
              child: Container(
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
                    color: const Color(0xFFFF2A85).withValues(alpha: 0.42),
                    width: 1.4,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: _cycleMessage,
                    splashColor: const Color(0xFFFF2A85).withValues(alpha: 0.25),
                    highlightColor: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Pulsing Neon Heart with Glow halo
                          ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              padding: const EdgeInsets.all(11),
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
                                size: 21,
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),

                          // Text with AnimatedSwitcher for smooth message cross-fade & slide
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'MELODY OF MY HEART',
                                      style: TextStyle(
                                        color: Color(0xFFFF85BC),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF2A85)
                                            .withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: const Color(0xFFFF2A85)
                                              .withValues(alpha: 0.40),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.auto_awesome_rounded,
                                            size: 10,
                                            color: Color(0xFFFF85BC),
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Dr. Basbosa 💕',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
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
                                  duration: const Duration(milliseconds: 350),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0.0, 0.15),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: Text(
                                    _loveQuotes[_currentIndex],
                                    key: ValueKey<int>(_currentIndex),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.8,
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
                                    const Text(
                                      '— Eng. Eslam ✨',
                                      style: TextStyle(
                                        color: Color(0xFFFF85BC),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    Text(
                                      'Tap for new message 💌',
                                      style: TextStyle(
                                        color: p.textTertiary
                                            .withValues(alpha: 0.65),
                                        fontSize: 9.5,
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
            ),
          ),
        );
      },
    );
  }
}
