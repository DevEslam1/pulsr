// lib/features/onboarding/presentation/onboarding_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/services/sound_feedback_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/pulsr_haptics.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_logo.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../settings/cubit/settings_cubit.dart';

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

  /// Total walkthrough pages (privacy, playback, beauty, gestures, personalize).
  static const int _pageCount = 5;
  int get _lastPage => _pageCount - 1;

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
    } catch (e, st) {
      ErrorLogger.log(
        'Onboarding permission grant flow failed',
        error: e,
        stackTrace: st,
        category: 'Onboarding',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(context.l10n.somethingWentWrong),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: context.l10n.skipAction,
                onPressed: _completeOnboarding,
              ),
            ),
          );
      }
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
          await _setNotificationDeniedPref(true);
          if (mounted && messenger != null) {
            messenger
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  content: Text(msg),
                  behavior: SnackBarBehavior.floating,
                  action: SnackBarAction(
                    label: context.l10n.openSettings,
                    onPressed: _openNotificationSettings,
                  ),
                ),
              );
          }
        } else if (status.isGranted) {
          await _setNotificationDeniedPref(false);
        }
      } catch (e, st) {
        final messenger = mounted ? ScaffoldMessenger.of(context) : null;
        final msg = mounted ? context.l10n.onboardingNotificationDenied : '';
        await _setNotificationDeniedPref(true);
        ErrorLogger.log(
          'Notification permission request failed',
          error: e,
          stackTrace: st,
          category: 'Onboarding',
        );
        if (mounted && messenger != null) {
          messenger
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(msg),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: context.l10n.openSettings,
                  onPressed: _openNotificationSettings,
                ),
              ),
            );
        }
      }
    } else {
      // "Not now" is a deliberate deferral, not a denial. Marking it denied
      // made Home show a persistent nag banner for a permission the user never
      // refused at the OS level.
      await _setNotificationDeniedPref(false);
    }
  }

  /// Opens the system notification settings and refreshes the persisted
  /// denial flag from the real OS state when the user returns, so the home
  /// banner is not shown for a permission that was just granted.
  Future<void> _openNotificationSettings() async {
    await openAppSettings();
    try {
      final status = await Permission.notification.status;
      await _setNotificationDeniedPref(
        status.isDenied || status.isPermanentlyDenied,
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to re-check notification permission',
        error: e,
        stackTrace: st,
        category: 'Onboarding',
      );
    }
  }

  /// Persists the notification-denied flag without letting a SharedPreferences
  /// failure escape the notification catch path (a throw here would surface as
  /// an unhandled async error and skip the user-facing snackbar).
  Future<void> _setNotificationDeniedPref(bool denied) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_permission_denied', denied);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to persist notification permission flag',
        error: e,
        stackTrace: st,
        category: 'Onboarding',
      );
    }
  }

  Future<void> _scanLibrary() async {
    try {
      await widget.scannerService.scanDeviceLibrary();
    } catch (e, st) {
      ErrorLogger.log(
        'Library scan failed during onboarding',
        error: e,
        stackTrace: st,
        category: 'Onboarding',
      );
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

    if (action == 'limited') {
      await _completeOnboarding();
    } else if (action == 'settings') {
      await openAppSettings();
    }
    // A null result (barrier tap / back) means the user dismissed the dialog
    // without choosing: keep onboarding open and leave the CTA tappable.
  }

  Future<void> _completeOnboarding() async {
    try {
      SoundFeedbackService.playSuccess(mirrorHaptics: true);
    } catch (e, st) {
      ErrorLogger.log(
        'SoundFeedbackService failed',
        error: e,
        stackTrace: st,
        category: 'Onboarding',
      );
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed', true);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to save onboarding_completed pref',
        error: e,
        stackTrace: st,
        category: 'Onboarding',
      );
    }
    if (mounted) {
      context.go('/');
    }
  }

  void _nextPage() {
    SoundFeedbackService.playClick(mirrorHaptics: true);
    if (_currentPage < _lastPage) {
      _pageController.nextPage(
        duration: context.motionMs(350),
        curve: context.motionCurve(Curves.easeInOut),
      );
    }
  }

  void _previousPage() {
    SoundFeedbackService.playClick(mirrorHaptics: true);
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: context.motionMs(300),
        curve: context.motionCurve(Curves.easeInOut),
      );
    }
  }

  void _jumpToPage(int index) {
    if (index == _currentPage) return;
    PulsrHaptics.selection();
    _pageController.animateToPage(
      index,
      duration: context.motionMs(350),
      curve: context.motionCurve(Curves.easeInOut),
    );
  }

  void _skipToFinal() {
    SoundFeedbackService.playClick(mirrorHaptics: true);
    _pageController.animateToPage(
      _lastPage,
      duration: context.motionMs(400),
      curve: context.motionCurve(Curves.easeInOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isLandscape = context.isLandscape;

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        children: [
          // Subtle ambient radial glow tied to the active accent color
          Positioned(
            top: -120,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: context.motionMs(450),
                height: 360,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      p.accent.withValues(alpha: p.isDark ? 0.14 : 0.10),
                      Colors.transparent,
                    ],
                    radius: 0.85,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ---------- Top Bar with Brand, Step Pill & Skip ----------
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: isLandscape ? AppSpacing.xxs : AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s10,
                              vertical: AppSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.12),
                              borderRadius: AppRadii.r10All,
                              border: Border.all(
                                color: p.accent.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.graphic_eq_rounded,
                                  size: 16,
                                  color: p.accent,
                                ),
                                const SizedBox(width: AppSpacing.xxs),
                                Text(
                                  'PULSR',
                                  style: TextStyle(
                                    fontSize: AppFontSize.label,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: AppTracking.widest,
                                    color: p.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: AppSpacing.s2,
                            ),
                            decoration: BoxDecoration(
                              color: p.surfaceContainer,
                              borderRadius: AppRadii.r8All,
                              border: Border.all(color: p.hairline),
                            ),
                            child: Text(
                              '${_currentPage + 1} / $_pageCount',
                              style: TextStyle(
                                fontSize: AppFontSize.tiny,
                                fontWeight: FontWeight.w700,
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (_currentPage < _lastPage)
                            TextButton.icon(
                              onPressed: _skipToFinal,
                              style: TextButton.styleFrom(
                                foregroundColor: p.textSecondary,
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppRadii.r10All,
                                ),
                              ),
                              iconAlignment: IconAlignment.end,
                              icon: const Icon(
                                Icons.keyboard_double_arrow_right_rounded,
                                size: 16,
                              ),
                              label: Text(
                                context.l10n.skipAction,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.label,
                                ),
                              ),
                            )
                          else
                            SizedBox(
                              height:
                                  isLandscape ? AppSpacing.lg : AppSpacing.s32,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ---------- PageView Walkthrough ----------
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    children: [
                      _buildPage1(context),
                      _buildPage2(context),
                      _buildPage3(context),
                      _buildPage4(context),
                      _buildPage5(context),
                    ],
                  ),
                ),

                // ---------- Bottom Navigation & Page Indicators ----------
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.s28,
                        AppSpacing.xs,
                        AppSpacing.s28,
                        isLandscape ? AppSpacing.sm : AppSpacing.lg,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Interactive Page Indicators (Dots)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(_pageCount, (index) {
                              final isActive = index == _currentPage;
                              return Semantics(
                                button: true,
                                selected: isActive,
                                label: context.l10n.onboardingPageIndicator(
                                  index + 1,
                                  _pageCount,
                                ),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _jumpToPage(index),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.xxs,
                                      vertical: AppSpacing.xs,
                                    ),
                                    child: AnimatedContainer(
                                      duration: context.motionMs(300),
                                      curve: Curves.easeOutCubic,
                                      height: isLandscape ? 6 : 8,
                                      width: isActive
                                          ? (isLandscape ? 22 : 28)
                                          : (isLandscape ? 6 : 8),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? p.accent
                                            : p.hairline.withValues(alpha: 0.8),
                                        borderRadius: AppRadii.r4All,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          SizedBox(
                            height: isLandscape ? AppSpacing.xs : AppSpacing.md,
                          ),

                          // Navigation Buttons Row (Back + Next / Grant Access)
                          SizedBox(
                            height: isLandscape ? 44 : 52,
                            child: Row(
                              children: [
                                if (_currentPage > 0) ...[
                                  SizedBox(
                                    width: isLandscape ? 44 : 52,
                                    height: isLandscape ? 44 : 52,
                                    child: IconButton.outlined(
                                      style: IconButton.styleFrom(
                                        foregroundColor: p.textPrimary,
                                        side: BorderSide(color: p.hairline),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: AppRadii.r16All,
                                        ),
                                      ),
                                      onPressed:
                                          _isLoading ? null : _previousPage,
                                      icon: Icon(
                                        Icons.adaptive.arrow_back_rounded,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                ],
                                Expanded(
                                  child: _currentPage == _lastPage
                                      ? FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: p.accent,
                                            foregroundColor: p.onAccent,
                                            minimumSize: Size.fromHeight(
                                              isLandscape ? 44 : 52,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: AppRadii.r16All,
                                            ),
                                            elevation: 2,
                                          ),
                                          onPressed: _isLoading
                                              ? null
                                              : _handleGrantAccess,
                                          child: _isLoading
                                              ? SizedBox(
                                                  height: 22,
                                                  width: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    color: p.onAccent,
                                                  ),
                                                )
                                              : Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(
                                                      Icons.shield_rounded,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(
                                                      width: AppSpacing.xs,
                                                    ),
                                                    Text(
                                                      context.l10n.grantAccess,
                                                      style: const TextStyle(
                                                        fontSize: AppFontSize
                                                            .bodyLarge,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        )
                                      : FilledButton.tonal(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                p.surfaceContainerHigh,
                                            foregroundColor: p.textPrimary,
                                            minimumSize: Size.fromHeight(
                                              isLandscape ? 44 : 52,
                                            ),
                                            side: BorderSide(
                                              color: p.hairline,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: AppRadii.r16All,
                                            ),
                                          ),
                                          onPressed: _nextPage,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                context.l10n.next,
                                                style: const TextStyle(
                                                  fontSize:
                                                      AppFontSize.bodyLarge,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(
                                                width: AppSpacing.xs,
                                              ),
                                              Icon(
                                                Icons.adaptive
                                                    .arrow_forward_rounded,
                                                size: 20,
                                                color: p.accent,
                                              ),
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
                  ),
                ),
              ],
            ),
          ),
        ],
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
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.md),
              Container(
                padding: EdgeInsets.all(isLandscape ? 10 : 16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: p.accent.withValues(alpha: 0.18),
                  ),
                ),
                child: Container(
                  width: isLandscape ? 72 : 108,
                  height: isLandscape ? 72 : 108,
                  decoration: BoxDecoration(
                    color: p.surfaceCard,
                    borderRadius:
                        isLandscape ? AppRadii.r20All : AppRadii.r28All,
                    border: Border.all(color: p.hairline, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: p.accent.withValues(alpha: 0.22),
                        blurRadius: 36,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: PulsrLogo(
                      size: isLandscape ? 42 : 64,
                      color: p.accent,
                      glowColor: p.glow,
                      animate: true,
                    ),
                  ),
                ),
              ).animate().scale(
                    duration: context.motionMs(600),
                    curve: context.motionCurve(Curves.easeOutBack),
                  ),
              SizedBox(height: isLandscape ? AppSpacing.md : AppSpacing.s32),
              Text(
                context.l10n.onboardingHeading,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.heading,
                      color: p.textPrimary,
                    ),
              )
                  .animate()
                  .fadeIn(delay: context.motionMs(200))
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.onboardingPrivacyDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: p.textSecondary,
                      height: 1.5,
                    ),
              )
                  .animate()
                  .fadeIn(delay: context.motionMs(350))
                  .slideY(begin: 0.1, end: 0),
              SizedBox(height: isLandscape ? AppSpacing.md : AppSpacing.xl),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.s14,
                ),
                decoration: BoxDecoration(
                  color: p.surfaceCard,
                  borderRadius: AppRadii.r18All,
                  border: Border.all(color: p.hairline),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.s10),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: AppRadii.r12All,
                      ),
                      child: Icon(
                        Icons.verified_user_rounded,
                        color: p.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        context.l10n.privacyGuarantee,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: AppFontSize.bodySmall,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: context.motionMs(450)),
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
    const eqHeights = <double>[12, 22, 30, 18, 28, 34, 24, 16, 26, 14];

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
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.md),
              // Audiophile DSP Rack Card
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  vertical: isLandscape ? AppSpacing.sm : AppSpacing.lg,
                  horizontal: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: p.surfaceCard,
                  borderRadius: isLandscape ? AppRadii.r18All : AppRadii.r24All,
                  border: Border.all(
                    color: p.accent.withValues(alpha: 0.28),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.14),
                      blurRadius: 32,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    if (!isLandscape) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final h in eqHeights)
                            Container(
                              width: 6,
                              height: h,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                borderRadius: AppRadii.r4All,
                                gradient: LinearGradient(
                                  colors: [
                                    p.accent,
                                    p.accent.withValues(alpha: 0.35),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Divider(
                        height: 1,
                        color: p.hairline.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: _buildPlaybackFeatureIcon(
                            Icons.equalizer_rounded,
                            context.l10n.browseTenBandGraphicEq,
                            p.accent,
                          ),
                        ),
                        Expanded(
                          child: _buildPlaybackFeatureIcon(
                            Icons.tune_rounded,
                            context.l10n.browseCrossfade,
                            p.info,
                          ),
                        ),
                        Expanded(
                          child: _buildPlaybackFeatureIcon(
                            Icons.timer_rounded,
                            context.l10n.sleepTimer,
                            p.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: context.motionMs(500))
                  .scale(begin: const Offset(0.92, 0.92)),
              SizedBox(height: isLandscape ? AppSpacing.md : AppSpacing.s32),
              Text(
                context.l10n.onboardingPowerful,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.heading,
                      color: p.textPrimary,
                    ),
              )
                  .animate()
                  .fadeIn(delay: context.motionMs(200))
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.onboardingPowerfulDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: p.textSecondary,
                      height: 1.5,
                    ),
              )
                  .animate()
                  .fadeIn(delay: context.motionMs(350))
                  .slideY(begin: 0.1, end: 0),
              SizedBox(height: isLandscape ? AppSpacing.sm : AppSpacing.lg),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _FeatureBadge(
                    icon: Icons.graphic_eq_rounded,
                    label: context.l10n.browseTenBandGraphicEq,
                  ),
                  _FeatureBadge(
                    icon: Icons.compare_arrows_rounded,
                    label: context.l10n.browseSmoothCrossfade,
                  ),
                  _FeatureBadge(
                    icon: Icons.bedtime_rounded,
                    label: context.l10n.sleepTimer,
                  ),
                  _FeatureBadge(
                    icon: Icons.all_inclusive_rounded,
                    label: context.l10n.gaplessPlayback,
                  ),
                ],
              ).animate().fadeIn(delay: context.motionMs(450)),
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
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.md),
              // Theme Swatches Showcase Card
              Container(
                padding: EdgeInsets.all(
                  isLandscape ? AppSpacing.sm : AppSpacing.s20,
                ),
                decoration: BoxDecoration(
                  color: p.surfaceCard,
                  borderRadius: isLandscape ? AppRadii.r18All : AppRadii.r24All,
                  border: Border.all(color: p.hairline, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.16),
                      blurRadius: 36,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s10,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.14),
                        borderRadius: AppRadii.r10All,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.palette_rounded,
                            color: p.accent,
                            size: 18,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            context.l10n.onboardingThemes,
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w800,
                              letterSpacing: AppTracking.wide,
                              color: p.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: isLandscape ? AppSpacing.xs : AppSpacing.md,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: _buildThemeSwatch(
                            'Pulsr Modern',
                            const [AppColors.primary, AppColors.secondary],
                          ),
                        ),
                        Expanded(
                          child: _buildThemeSwatch(
                            'Glassmorphism',
                            const [AppColors.swatchGreen, AppColors.mint],
                          ),
                        ),
                        Expanded(
                          child: _buildThemeSwatch(
                            'Dynamic Palette',
                            const [
                              AppColors.swatchAmber,
                              AppColors.swatchPink,
                            ],
                          ),
                        ),
                        Expanded(
                          child: _buildThemeSwatch(
                            'Cyberpunk Aura',
                            const [
                              AppColors.swatchPurple,
                              AppColors.skyBlue,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: context.motionMs(500))
                  .scale(begin: const Offset(0.92, 0.92)),
              SizedBox(height: isLandscape ? AppSpacing.md : AppSpacing.s32),
              Text(
                context.l10n.onboardingBeautiful,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.heading,
                      color: p.textPrimary,
                    ),
              )
                  .animate()
                  .fadeIn(delay: context.motionMs(200))
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.onboardingBeautifulDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: p.textSecondary,
                      height: 1.5,
                    ),
              )
                  .animate()
                  .fadeIn(delay: context.motionMs(350))
                  .slideY(begin: 0.1, end: 0),
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  // Page 4: "Gestures & shortcuts"
  Widget _buildPage4(BuildContext context) {
    final p = context.palette;
    final isLandscape = context.isLandscape;
    final gestures = <(IconData, String, String, Color)>[
      (
        Icons.swipe_up_rounded,
        context.l10n.onboardingGestureSwipeUpTitle,
        context.l10n.onboardingGestureSwipeUpDesc,
        p.accent,
      ),
      (
        Icons.swipe_down_rounded,
        context.l10n.onboardingGestureSwipeDownTitle,
        context.l10n.onboardingGestureSwipeDownDesc,
        p.info,
      ),
      (
        Icons.favorite_rounded,
        context.l10n.onboardingGestureDoubleTapTitle,
        context.l10n.onboardingGestureDoubleTapDesc,
        p.favorite,
      ),
      (
        Icons.touch_app_rounded,
        context.l10n.onboardingGestureLongPressTitle,
        context.l10n.onboardingGestureLongPressDesc,
        p.primary,
      ),
    ];
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
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.sm),
              Text(
                context.l10n.onboardingGesturesTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.heading,
                      color: p.textPrimary,
                    ),
              )
                  .animate()
                  .fadeIn(delay: context.motionMs(150))
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.l10n.onboardingGesturesDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: p.textSecondary,
                      height: 1.45,
                    ),
              )
                  .animate()
                  .fadeIn(delay: context.motionMs(300))
                  .slideY(begin: 0.1, end: 0),
              SizedBox(height: isLandscape ? AppSpacing.sm : AppSpacing.md),
              Column(
                children: [
                  for (final (icon, title, desc, color) in gestures)
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.s10,
                      ),
                      decoration: BoxDecoration(
                        color: p.surfaceCard,
                        borderRadius: AppRadii.r16All,
                        border: Border.all(color: p.hairline),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: AppRadii.r12All,
                            ),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: p.textPrimary,
                                    fontSize: AppFontSize.bodySmall,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  desc,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.label,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ).animate().fadeIn(delay: context.motionMs(400)),
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  // Page 5: "Make it yours"
  Widget _buildPage5(BuildContext context) {
    final p = context.palette;
    final isLandscape = context.isLandscape;
    final selected = context
        .select<SettingsCubit, int>((c) => c.state.customAccentColorValue);
    final cubit = context.read<SettingsCubit>();

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
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.s20),
                decoration: BoxDecoration(
                  color: p.surfaceCard,
                  borderRadius: isLandscape ? AppRadii.r18All : AppRadii.r24All,
                  border: Border.all(
                    color: p.accent.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.16),
                      blurRadius: 36,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Live interactive mini-player preview banner
                    AnimatedContainer(
                      duration: context.motionMs(250),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.12),
                        borderRadius: AppRadii.r14All,
                        border: Border.all(
                          color: p.accent.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: p.accent,
                              borderRadius: AppRadii.r10All,
                            ),
                            child: Icon(
                              Icons.music_note_rounded,
                              color: p.onAccent,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pulsr Audio Engine',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppFontSize.label,
                                    fontWeight: FontWeight.w800,
                                    color: p.textPrimary,
                                  ),
                                ),
                                Text(
                                  '24-bit / 192kHz • FLAC',
                                  style: TextStyle(
                                    fontSize: AppFontSize.tiny,
                                    fontWeight: FontWeight.w700,
                                    color: p.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.play_circle_fill_rounded,
                            color: p.accent,
                            size: 28,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      alignment: WrapAlignment.center,
                      children: AppColors.customAccents.indexed.map((entry) {
                        final index = entry.$1;
                        final color = entry.$2;
                        final isSelected = selected == color.toARGB32();
                        return Semantics(
                          button: true,
                          selected: isSelected,
                          label:
                              '${context.l10n.customAccentColor} ${index + 1}',
                          child: GestureDetector(
                            onTap: () {
                              PulsrHaptics.selection();
                              SoundFeedbackService.playClick();
                              cubit.setCustomAccentColor(color);
                            },
                            child: AnimatedContainer(
                              duration: context.motionMs(200),
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? p.textPrimary
                                      : Colors.transparent,
                                  width: isSelected ? 3 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.45),
                                          blurRadius: 12,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: isSelected
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: color.computeLuminance() > 0.5
                                          ? Colors.black
                                          : Colors.white,
                                      size: 22,
                                    )
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: context.motionMs(500))
                  .scale(begin: const Offset(0.92, 0.92)),
              SizedBox(height: isLandscape ? AppSpacing.md : AppSpacing.s32),
              Text(
                context.l10n.onboardingPersonalizeTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.heading,
                      color: p.textPrimary,
                    ),
              )
                  .animate()
                  .fadeIn(delay: context.motionMs(200))
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.onboardingPersonalizeDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: p.textSecondary,
                      height: 1.5,
                    ),
              )
                  .animate()
                  .fadeIn(delay: context.motionMs(350))
                  .slideY(begin: 0.1, end: 0),
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
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: AppRadii.r16All,
            border:
                Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
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
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: 0.38),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: p.surfaceCard.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureBadge({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: AppRadii.r20All,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: p.accent),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: AppFontSize.label,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
