// lib/features/onboarding/presentation/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/waveform_logo.dart';
import '../../../data/scanner/media_scanner_service.dart';

class OnboardingScreen extends StatefulWidget {
  final MediaScannerService scannerService;

  const OnboardingScreen({super.key, required this.scannerService});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _isLoading = false;

  Future<void> _handleGrantAccess() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final granted = await widget.scannerService.requestPermission();
      if (granted) {
        await widget.scannerService.scanDeviceLibrary();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.outline, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Center(child: WaveformLogo(size: 48)),
              ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 36),
              Text(
                AppStrings.onboardingTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
              const SizedBox(height: 16),
              Text(
                AppStrings.onboardingSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
              ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(color: AppColors.outline),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '100% offline. Zero telemetry, zero cloud tracking.',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 500.ms),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleGrantAccess,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                        )
                      : const Text(
                          AppStrings.grantAccess,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2, end: 0),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
