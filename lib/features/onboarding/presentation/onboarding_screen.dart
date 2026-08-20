// lib/features/onboarding/presentation/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/widgets/pulsr_logo.dart';
import '../../../data/scanner/media_scanner_service.dart';

class OnboardingScreen extends StatefulWidget {
  final MediaScannerService scannerService;

  const OnboardingScreen({super.key, required this.scannerService});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleGrantAccess() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final granted = await widget.scannerService.requestPermission();
      if (granted) {
        await widget.scannerService.scanDeviceLibrary();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Audio access is required to display your music library.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed', true);

      if (mounted) {
        context.go('/');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _skipToFinal() {
    _pageController.animateToPage(
      2,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Skip Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PULSR',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: p.accent,
                    ),
                  ),
                  if (_currentPage < 2)
                    TextButton(
                      onPressed: _skipToFinal,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: p.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 36),
                ],
              ),
            ),

            // PageView Walkthrough
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildPage1(context),
                  _buildPage2(context),
                  _buildPage3(context),
                ],
              ),
            ),

            // Bottom Navigation & Page Indicators
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Page Indicators (Dots)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (index) {
                      final isActive = index == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: isActive ? 24 : 8,
                        decoration: BoxDecoration(
                          color:
                              isActive ? p.accent : p.hairline,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),

                  // Navigation Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: _currentPage == 2
                        ? ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: p.accent,
                              foregroundColor: p.onAccent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: AppRadii.cardRadius),
                              elevation: 4,
                            ),
                            onPressed: _isLoading ? null : _handleGrantAccess,
                            child: _isLoading
                                ? SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: p.onAccent,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.shield_rounded, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Grant Access & Start Listening',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                          )
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: p.surfaceContainer,
                              foregroundColor: p.textPrimary,
                              side: BorderSide(
                                  color: p.hairline, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: AppRadii.cardRadius),
                            ),
                            onPressed: _nextPage,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Next',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded,
                                    size: 20, color: p.accent),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Page 1: "Your Music, Your Privacy"
  Widget _buildPage1(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: p.hairline, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.25),
                  blurRadius: 36,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: Center(
              child: PulsrLogo(
                size: 64,
                color: p.accent,
                glowColor: p.glow,
                animate: true,
              ),
            ),
          ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 36),
          Text(
            'Your Music, Your Privacy',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
          const SizedBox(height: 16),
          Text(
            '100% offline local playback. No accounts, no cloud dependencies, zero tracking, and absolute privacy for your music collection.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: p.textSecondary,
                  height: 1.5,
                ),
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_rounded, color: p.accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '100% Offline • Zero Telemetry • Local Storage',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 500.ms),
          const Spacer(),
        ],
      ),
    );
  }

  // Page 2: "Powerful Playback"
  Widget _buildPage2(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          // Graphic container representing EQ & Audio Controls
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: p.accent.withValues(alpha: 0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.15),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPlaybackFeatureIcon(
                    Icons.equalizer_rounded, '5-Band EQ', p.accent),
                _buildPlaybackFeatureIcon(
                    Icons.tune_rounded, 'Crossfade', p.accent),
                _buildPlaybackFeatureIcon(
                    Icons.timer_rounded, 'Sleep Timer', p.accent),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(begin: const Offset(0.9, 0.9)),
          const SizedBox(height: 36),
          Text(
            'Powerful Playback',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
          const SizedBox(height: 16),
          Text(
            'Tailor your sound with a 5-band parametric equalizer, smooth crossfade transitions, gapless playback, and smart sleep timers.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: p.textSecondary,
                  height: 1.5,
                ),
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: const [
              _FeatureBadge(label: '5-Band Equalizer'),
              _FeatureBadge(label: 'Smooth Crossfade'),
              _FeatureBadge(label: 'Sleep Timer'),
              _FeatureBadge(label: 'Gapless Playback'),
            ],
          ).animate().fadeIn(delay: 500.ms),
          const Spacer(),
        ],
      ),
    );
  }

  // Page 3: "Beautiful & Personal"
  Widget _buildPage3(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          // Theme swatches visual container
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.hairline, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.2),
                  blurRadius: 36,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.palette_rounded,
                        color: p.accent, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      '4 DISTINCT PLAYER THEMES',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildThemeSwatch('Pulsr Modern',
                        const [Color(0xFF9B9EF5), Color(0xFF6C70DC)]),
                    _buildThemeSwatch('Glassmorphism',
                        const [Color(0xFF00E676), Color(0xFF1DE9B6)]),
                    _buildThemeSwatch('Dynamic Palette',
                        const [Color(0xFFFF9100), Color(0xFFFF4081)]),
                    _buildThemeSwatch('Cyberpunk Aura',
                        const [Color(0xFFD500F9), Color(0xFF40C4FF)]),
                  ],
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(begin: const Offset(0.9, 0.9)),
          const SizedBox(height: 36),
          Text(
            'Beautiful & Personal',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
          const SizedBox(height: 16),
          Text(
            'Express your style with real-time dynamic color extraction from album art and switch between 4 unique player themes.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: p.textSecondary,
                  height: 1.5,
                ),
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildPlaybackFeatureIcon(IconData icon, String label, Color color) {
    final p = context.palette;
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildThemeSwatch(String name, List<Color> colors) {
    final p = context.palette;
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: 0.4),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 64,
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  final String label;

  const _FeatureBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.hairline),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: p.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
