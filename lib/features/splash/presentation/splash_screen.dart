// lib/features/splash/presentation/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/waveform_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkNextScreen();
  }

  Future<void> _checkNextScreen() async {
    await Future.delayed(const Duration(milliseconds: 1600));
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: WaveformLogo(size: 64),
            )
                .animate()
                .scale(duration: const Duration(milliseconds: 800), curve: Curves.easeOutBack)
                .fadeIn(duration: const Duration(milliseconds: 600)),
            const SizedBox(height: 24),
            Text(
              AppStrings.appName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
            )
                .animate()
                .fadeIn(delay: const Duration(milliseconds: 300), duration: const Duration(milliseconds: 600))
                .slideY(begin: 0.2, end: 0),
            const SizedBox(height: 8),
            Text(
              AppStrings.appTagline,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
            )
                .animate()
                .fadeIn(delay: const Duration(milliseconds: 500), duration: const Duration(milliseconds: 600)),
          ],
        ),
      ),
    );
  }
}
