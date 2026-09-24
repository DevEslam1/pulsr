// lib/features/onboarding/presentation/onboarding_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_logo.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../data/scanner/media_scanner_service.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

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
    setState(() => _isLoading = true);
    try {
      final granted = await widget.scannerService.requestPermission();
      if (!granted) {
        if (mounted) await _handleDeniedStorageAccess();
        return;
      }

      if (Platform.isAndroid && mounted) {
        await _requestNotificationPermission();
      }

      await _scanLibrary();
      await _completeOnboarding();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    final allow = await PulsrDialogHelper.showCustomDialog<bool>(
      context,
      builder: (ctx) => PulsrDialog(
        title: context.l10n.notificationPermissionTitle,
        icon: Icons.notifications_active_rounded,
        content: Text(context.l10n.notificationPermissionRationale),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.notificationPermissionNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.notificationPermissionAllow),
          ),
        ],
      ),
    );

    if (allow == true && mounted) {
      try {
        final status = await Permission.notification.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          final messenger = mounted ? ScaffoldMessenger.of(context) : null;
          final msg = mounted ? context.l10n.onboardingNotificationDenied : '';
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('notification_permission_denied', true);
          if (mounted && messenger != null) {
            messenger
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                      '$msg Notifications are needed for playback controls.'),
                  behavior: SnackBarBehavior.floating,
                  action: SnackBarAction(label: 'OK', onPressed: () {}),
                ),
              );
          }
        } else if (status.isGranted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('notification_permission_denied', false);
        }
      } catch (e, st) {
        final messenger = mounted ? ScaffoldMessenger.of(context) : null;
        final msg = mounted ? context.l10n.onboardingNotificationDenied : '';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('notification_permission_denied', true);
        ErrorLogger.log('Notification permission request failed',
            error: e, stackTrace: st, category: 'Onboarding');
        if (mounted && messenger != null) {
          messenger
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(msg),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(label: 'OK', onPressed: () {}),
              ),
            );
        }
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_permission_denied', true);
    }
  }

  Future<void> _scanLibrary() async {
    try {
      await widget.scannerService.scanDeviceLibrary();
    } catch (e, st) {
      ErrorLogger.log('Library scan failed during onboarding',
          error: e, stackTrace: st, category: 'Onboarding');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(context.l10n.onboardingScanFailed)),
          );
      }
    }
  }

  Future<void> _handleDeniedStorageAccess() async {
    final action = await PulsrDialogHelper.showCustomDialog<String>(
      context,
      builder: (ctx) => PulsrDialog(
        title: context.l10n.audioAccessRequired,
        icon: Icons.folder_shared_rounded,
        content: Text(context.l10n.onboardingPermissionRationale),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'limited'),
            child: Text(context.l10n.continueLimitedAccess),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'settings'),
            child: Text(context.l10n.openSettings),
          ),
        ],
      ),
    );

    if (action == 'settings') {
      await openAppSettings();
      return;
    }

    await _completeOnboarding();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    if (mounted) {
      context.go('/');
    }
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: context.motionMs(350),
        curve: context.motionCurve(Curves.easeInOut),
      );
    }
  }

  void _skipToFinal() {
    _pageController.animateToPage(
      2,
      duration: context.motionMs(400),
      curve: context.motionCurve(Curves.easeInOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isLandscape = context.isLandscape;

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Skip Button
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: isLandscape ? AppSpacing.xs : AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PULSR',
                    style: TextStyle(
                      fontSize: AppFontSize.bodyLarge,
                      fontWeight: FontWeight.w900,
                      letterSpacing: AppTracking.widest,
                      color: p.accent,
                    ),
                  ),
                  if (_currentPage < 2)
                    TextButton(
                      onPressed: _skipToFinal,
                      child: Text(context.l10n.skipAction,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    SizedBox(height: isLandscape ? AppSpacing.lg : AppSpacing.s40),
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
              padding: EdgeInsetsDirectional.fromSTEB(
                AppSpacing.s28,
                0,
                AppSpacing.s28,
                isLandscape ? AppSpacing.sm : AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Page Indicators (Dots)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (index) {
                      final isActive = index == _currentPage;
                      return AnimatedContainer(
                        duration: context.motionMs(300),
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                        height: isLandscape ? 6 : 8,
                        width: isActive ? (isLandscape ? 18 : 24) : (isLandscape ? 6 : 8),
                        decoration: BoxDecoration(
                          color: isActive ? p.accent : p.hairline,
                          borderRadius: BorderRadius.circular(AppRadii.r4),
                        ),
                      );
                    }),
                  ),
                  SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.lg),

                  // Navigation Button
                  SizedBox(
                    width: double.infinity,
                    height: isLandscape ? 44 : 52,
                    child: _currentPage == 2
                        ? FilledButton(
                            style: FilledButton.styleFrom(
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
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.shield_rounded,
                                          size: 20),
                                      const SizedBox(width: AppSpacing.xs),
                                      Text(
                                        context.l10n.grantAccess,
                                        style: const TextStyle(
                                          fontSize: AppFontSize.bodyLarge,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                          )
                        : OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: p.textPrimary,
                              side: BorderSide(color: p.hairline, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: AppRadii.cardRadius),
                            ),
                            onPressed: _nextPage,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  context.l10n.next,
                                  style: const TextStyle(
                                      fontSize: AppFontSize.bodyLarge,
                                      fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Icon(Icons.adaptive.arrow_forward_rounded,
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
    final isLandscape = context.isLandscape;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s28,
            vertical: isLandscape ? AppSpacing.xs : AppSpacing.md,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.lg),
              Container(
                width: isLandscape ? 68 : 104,
                height: isLandscape ? 68 : 104,
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: BorderRadius.circular(
                      isLandscape ? AppRadii.r20 : AppRadii.r28),
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
                    size: isLandscape ? 40 : 64,
                    color: p.accent,
                    glowColor: p.glow,
                    animate: true,
                  ),
                ),
              ).animate().scale(
                  duration: context.motionMs(600),
                  curve: context.motionCurve(Curves.easeOutBack)),
              SizedBox(height: isLandscape ? AppSpacing.md : AppSpacing.s40),
              Text(
                context.l10n.onboardingHeading,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.heading,
                    ),
              ).animate().fadeIn(delay: context.motionMs(200)).slideY(begin: 0.1, end: 0),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.onboardingPrivacyDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: p.textSecondary,
                      height: 1.5,
                    ),
              ).animate().fadeIn(delay: context.motionMs(400)).slideY(begin: 0.1, end: 0),
              SizedBox(height: isLandscape ? AppSpacing.md : AppSpacing.xl),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.s14),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(color: p.hairline),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_rounded, color: p.accent, size: 22),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        context.l10n.privacyGuarantee,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: AppFontSize.bodySmall,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: context.motionMs(500)),
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  // Page 2: "Powerful Playback"
  Widget _buildPage2(BuildContext context) {
    final p = context.palette;
    final isLandscape = context.isLandscape;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s28,
            vertical: isLandscape ? AppSpacing.xs : AppSpacing.md,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.lg),
              // Graphic container representing EQ & Audio Controls
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                    vertical: isLandscape ? AppSpacing.sm : AppSpacing.lg,
                    horizontal: AppSpacing.s20),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: BorderRadius.circular(
                      isLandscape ? AppRadii.r18 : AppRadii.r24),
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
                    _buildPlaybackFeatureIcon(Icons.equalizer_rounded,
                        context.l10n.browseTenBandGraphicEq, p.accent),
                    _buildPlaybackFeatureIcon(
                        Icons.tune_rounded, context.l10n.browseCrossfade, p.accent),
                    _buildPlaybackFeatureIcon(
                        Icons.timer_rounded, context.l10n.sleepTimer, p.accent),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: context.motionMs(500))
                  .scale(begin: const Offset(0.9, 0.9)),
              SizedBox(height: isLandscape ? AppSpacing.md : AppSpacing.s40),
              Text(
                context.l10n.onboardingPowerful,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.heading,
                    ),
              ).animate().fadeIn(delay: context.motionMs(200)).slideY(begin: 0.1, end: 0),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.onboardingPowerfulDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: p.textSecondary,
                      height: 1.5,
                    ),
              ).animate().fadeIn(delay: context.motionMs(400)).slideY(begin: 0.1, end: 0),
              SizedBox(height: isLandscape ? AppSpacing.sm : AppSpacing.lg),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _FeatureBadge(label: context.l10n.browseTenBandGraphicEq),
                  _FeatureBadge(label: context.l10n.browseSmoothCrossfade),
                  _FeatureBadge(label: context.l10n.sleepTimer),
                  _FeatureBadge(label: context.l10n.gaplessPlayback),
                ],
              ).animate().fadeIn(delay: context.motionMs(500)),
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  // Page 3: "Beautiful & Personal"
  Widget _buildPage3(BuildContext context) {
    final p = context.palette;
    final isLandscape = context.isLandscape;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s28,
            vertical: isLandscape ? AppSpacing.xs : AppSpacing.md,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.lg),
              // Theme swatches visual container
              Container(
                padding: EdgeInsets.all(
                    isLandscape ? AppSpacing.sm : AppSpacing.s20),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: BorderRadius.circular(
                      isLandscape ? AppRadii.r18 : AppRadii.r24),
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
                        Icon(Icons.palette_rounded, color: p.accent, size: 24),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          context.l10n.onboardingThemes,
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w800,
                            letterSpacing: AppTracking.wide,
                            color: p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.md),
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
                            const [Color(0xFFD500F9), AppColors.skyBlue]),
                      ],
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: context.motionMs(500))
                  .scale(begin: const Offset(0.9, 0.9)),
              SizedBox(height: isLandscape ? AppSpacing.md : AppSpacing.s40),
              Text(
                context.l10n.onboardingBeautiful,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.heading,
                    ),
              ).animate().fadeIn(delay: context.motionMs(200)).slideY(begin: 0.1, end: 0),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.onboardingBeautifulDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: p.textSecondary,
                      height: 1.5,
                    ),
              ).animate().fadeIn(delay: context.motionMs(400)).slideY(begin: 0.1, end: 0),
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.lg),
            ],
          ),
        ),
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
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: AppFontSize.label,
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
        const SizedBox(height: AppSpacing.s6),
        SizedBox(width: AppSpacing.s64,
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.tiny,
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.s6),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.r20),
        border: Border.all(color: p.hairline),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: p.textPrimary,
          fontSize: AppFontSize.label,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
