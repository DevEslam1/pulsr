// lib/features/splash/presentation/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkNextScreen();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkNextScreen() async {
    await Future.delayed(const Duration(milliseconds: 2300));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_completed') ?? false;

    if (!mounted) return;
    if (onboardingDone) {
      context.go('/');
    } else {
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.15),
            radius: 1.3,
            colors: [
              Color(0xFF2C071E), // Rich burgundy wine center
              Color(0xFF190311), // Deep berry obsidian
              Color(0xFF0C0109), // Midnight black
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ambient glowing orbs in the background
            Positioned(
              top: size.height * 0.15,
              left: size.width * 0.1,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF2A85).withValues(alpha: 0.10),
                ),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(
                    begin: const Offset(0.8, 0.8),
                    end: const Offset(1.2, 1.2),
                    duration: const Duration(seconds: 4),
                    curve: Curves.easeInOut,
                  ),
            ),
            Positioned(
              bottom: size.height * 0.2,
              right: size.width * 0.1,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF7BB0).withValues(alpha: 0.08),
                ),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(
                    begin: const Offset(1.1, 1.1),
                    end: const Offset(0.85, 0.85),
                    duration: const Duration(seconds: 3),
                    curve: Curves.easeInOut,
                  ),
            ),

            // Foreground main content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top dedicated tag
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2A85).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFFF2A85).withValues(alpha: 0.38),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF2A85).withValues(alpha: 0.2),
                            blurRadius: 14,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            size: 13,
                            color: Color(0xFFFF2A85),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'SPECIAL EDITION FOR DR. BASBOSA',
                            style: TextStyle(
                              color: Color(0xFFFF85BC),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn(duration: const Duration(milliseconds: 600))
                        .slideY(begin: -0.3, end: 0),

                    // Center Icon & App Title
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Animated pulsing App Icon
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF2A85).withValues(alpha: 0.5),
                                  blurRadius: 40,
                                  spreadRadius: 4,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: const Color(0xFFFF7BB0).withValues(alpha: 0.3),
                                  blurRadius: 60,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset(
                                'assets/app_icon/appicon2.png',
                                width: 110,
                                height: 110,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        )
                            .animate()
                            .scale(
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeOutBack,
                            )
                            .fadeIn(duration: const Duration(milliseconds: 600)),

                        const SizedBox(height: 28),

                        // Title
                        const Text(
                          'Pulsr Music',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            color: Colors.white,
                          ),
                        )
                            .animate()
                            .fadeIn(
                              delay: const Duration(milliseconds: 300),
                              duration: const Duration(milliseconds: 600),
                            )
                            .slideY(begin: 0.25, end: 0),

                        const SizedBox(height: 6),

                        // Subtitle
                        const Text(
                          'Dr. Basbosa\'s Sanctuary of Sound ✨',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF6D8E8),
                            letterSpacing: 0.3,
                          ),
                        )
                            .animate()
                            .fadeIn(
                              delay: const Duration(milliseconds: 450),
                              duration: const Duration(milliseconds: 600),
                            ),

                        const SizedBox(height: 18),

                        // Animated mini soundwave / dots
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (index) {
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2.5),
                              width: 3.5,
                              height: 16,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF2A85),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            )
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .scaleY(
                                  begin: 0.3,
                                  end: 1.2 + (index % 3) * 0.4,
                                  duration: Duration(milliseconds: 450 + index * 120),
                                  curve: Curves.easeInOut,
                                );
                          }),
                        )
                            .animate()
                            .fadeIn(delay: const Duration(milliseconds: 600)),
                      ],
                    ),

                    // Bottom Signature & Love Note
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Handcrafted with all my love ❤️',
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFFF6D8E8).withValues(alpha: 0.75),
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Eng. Eslam ✨',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFF85BC),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    )
                        .animate()
                        .fadeIn(
                          delay: const Duration(milliseconds: 700),
                          duration: const Duration(milliseconds: 600),
                        )
                        .slideY(begin: 0.2, end: 0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
