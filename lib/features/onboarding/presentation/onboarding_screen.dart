// lib/features/onboarding/presentation/onboarding_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/injection.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/services/sound_feedback_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/pulsr_haptics.dart';
import '../../../core/widgets/gestures_sheet.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_pressable.dart';
import '../../../core/widgets/pulsr_progress.dart';
import '../../../core/widgets/pulsr_segmented_control.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/presentation/themes/player_theme.dart';
import '../../player/presentation/themes/theme_registry.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../../settings/presentation/widgets/audio_setup_wizard.dart';

part 'onboarding_steps_part.dart';

class OnboardingScreen extends StatefulWidget {
  final MediaScannerService scannerService;

  const OnboardingScreen({super.key, required this.scannerService});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  StreamSubscription<ScanProgressUpdate>? _progressSub;
  int _currentPage = 0;
  bool _isLoading = false;
  bool _hasScanned = false;
  bool _notificationsGranted = false;
  int _scannedTrackCount = 0;
  double? _scanProgress;

  /// Total interactive walkthrough steps:
  /// 0: Welcome + Storage/Notification Permissions with live scanned track counter
  /// 1: Interactive Experience Mode (Normal vs Professional) + top 4 Player Themes live preview
  /// 2: Optional 1-tap AudioSetupWizard launch or "Start Listening" primary action
  static const int _pageCount = 3;
  int get _lastPage => _pageCount - 1;

  @override
  void initState() {
    super.initState();
    _bindProgressStream();
  }

  void _bindProgressStream() {
    try {
      final stream = widget.scannerService.detailedProgress;
      _progressSub = stream.listen((update) {
        if (!mounted) return;
        setState(() {
          _scannedTrackCount = update.scannedCount;
          _scanProgress = update.progress;
        });
      });
    } catch (_) {
      // Safe fallback when a mock scanner does not stub detailedProgress.
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  String _startListeningLabel(BuildContext context) =>
      context.l10n.onboardingStartListening;

  Widget _animateIfEnabled(
    BuildContext context,
    Widget child,
    Widget Function(Animate) effect,
  ) {
    if (!PulsrMotion.shouldAnimate(context)) return child;
    return effect(child.animate());
  }

  Future<void> _handleGrantAccess({bool completeOnSuccess = true}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final granted = await widget.scannerService.requestPermission();
      if (!granted) {
        if (mounted) {
          await _handleDeniedStorageAccess(
            completeOnSuccess: completeOnSuccess,
          );
        }
        return;
      }

      if (Platform.isAndroid && mounted) {
        await _requestNotificationPermission();
      }

      await _scanLibrary();
      if (completeOnSuccess) {
        await _completeOnboarding();
      }
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
                onPressed: completeOnSuccess ? _completeOnboarding : _nextPage,
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

  Future<void> _handleStartListening() async {
    if (_isLoading) return;
    if (_hasScanned) {
      await _completeOnboarding();
      return;
    }
    await _handleGrantAccess(completeOnSuccess: true);
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
          if (mounted) setState(() => _notificationsGranted = false);
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
          if (mounted) setState(() => _notificationsGranted = true);
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
    }
  }

  Future<void> _openNotificationSettings() async {
    await openAppSettings();
    try {
      final status = await Permission.notification.status;
      final denied = status.isDenied || status.isPermanentlyDenied;
      await _setNotificationDeniedPref(denied);
      if (mounted) {
        setState(() => _notificationsGranted = status.isGranted);
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to re-check notification permission',
        error: e,
        stackTrace: st,
        category: 'Onboarding',
      );
    }
  }

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
      final count = await widget.scannerService.scanDeviceLibrary();
      if (mounted) {
        setState(() {
          _scannedTrackCount = count;
          _hasScanned = true;
          _scanProgress = 1.0;
        });
      }
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

  Future<void> _handleDeniedStorageAccess({
    bool completeOnSuccess = true,
  }) async {
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
      if (completeOnSuccess) {
        await _completeOnboarding();
      } else {
        _nextPage();
      }
    } else if (action == 'settings') {
      await openAppSettings();
    }
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
      final target = _currentPage + 1;
      if (!PulsrMotion.shouldAnimate(context)) {
        _pageController.jumpToPage(target);
      } else {
        _pageController.nextPage(
          duration: context.motionMs(320),
          curve: context.motionCurve(Curves.easeInOut),
        );
      }
    }
  }

  void _previousPage() {
    SoundFeedbackService.playClick(mirrorHaptics: true);
    if (_currentPage > 0) {
      final target = _currentPage - 1;
      if (!PulsrMotion.shouldAnimate(context)) {
        _pageController.jumpToPage(target);
      } else {
        _pageController.previousPage(
          duration: context.motionMs(260),
          curve: context.motionCurve(Curves.easeInOut),
        );
      }
    }
  }

  void _jumpToPage(int index) {
    if (index == _currentPage) return;
    PulsrHaptics.selection();
    if (!PulsrMotion.shouldAnimate(context)) {
      _pageController.jumpToPage(index);
    } else {
      _pageController.animateToPage(
        index,
        duration: context.motionMs(320),
        curve: context.motionCurve(Curves.easeInOut),
      );
    }
  }

  void _skipToFinal() {
    SoundFeedbackService.playClick(mirrorHaptics: true);
    if (!PulsrMotion.shouldAnimate(context)) {
      _pageController.jumpToPage(_lastPage);
    } else {
      _pageController.animateToPage(
        _lastPage,
        duration: context.motionMs(400),
        curve: context.motionCurve(Curves.easeInOut),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isLandscape = context.isLandscape;
    final shouldAnimate = PulsrMotion.shouldAnimate(context);

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        children: [
          PositionedDirectional(
            top: -120,
            start: 0,
            end: 0,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: shouldAnimate ? context.motionMs(320) : Duration.zero,
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
                    constraints: const BoxConstraints(
                        maxWidth: PulsrLayoutMetrics.compactDialogMaxWidth),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: isLandscape ? AppSpacing.xxs : AppSpacing.xs,
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
                          Semantics(
                            liveRegion: true,
                            label: context.l10n.onboardingPageIndicator(
                              _currentPage + 1,
                              _pageCount,
                            ),
                            child: Container(
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
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w700,
                                  color: p.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: _currentPage < _lastPage
                                  ? TextButton(
                                      onPressed: _skipToFinal,
                                      style: TextButton.styleFrom(
                                        foregroundColor: p.textSecondary,
                                        minimumSize: const Size(
                                          AppSpacing.minTouchTarget,
                                          AppSpacing.minTouchTarget,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: AppRadii.r10All,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              context.l10n.skipAction,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: AppFontSize.label,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.xxs),
                                          const Icon(
                                            Icons
                                                .keyboard_double_arrow_right_rounded,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox(
                                      height: AppSpacing.minTouchTarget,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ---------- 3-Step Interactive PageView ----------
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    children: [
                      _buildStep1(context),
                      _buildStep2(context),
                      _buildStep3(context),
                    ],
                  ),
                ),

                // ---------- Bottom Navigation & Page Indicators ----------
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: PulsrLayoutMetrics.compactDialogMaxWidth),
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.s28,
                        AppSpacing.xxs,
                        AppSpacing.s28,
                        isLandscape ? AppSpacing.xs : AppSpacing.md,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minWidth: AppSpacing.minTouchTarget,
                                      minHeight: AppSpacing.minTouchTarget,
                                    ),
                                    child: Center(
                                      child: AnimatedContainer(
                                        duration: shouldAnimate
                                            ? context.motionMs(260)
                                            : Duration.zero,
                                        curve: context
                                            .motionCurve(PulsrMotion.enter),
                                        height: isLandscape ? 6 : 8,
                                        width: isActive
                                            ? (isLandscape ? 24 : 30)
                                            : (isLandscape ? 8 : 10),
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? p.accent
                                              : p.hairline
                                                  .withValues(alpha: 0.8),
                                          borderRadius: AppRadii.r4All,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          SizedBox(
                            height:
                                isLandscape ? AppSpacing.xxs : AppSpacing.xs,
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: AppSpacing.minTouchTarget,
                            ),
                            child: Row(
                              children: [
                                if (_currentPage > 0) ...[
                                  SizedBox(
                                    width: AppSpacing.minTouchTarget,
                                    height: AppSpacing.minTouchTarget,
                                    child: IconButton.outlined(
                                      tooltip: context.l10n.previous,
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
                                          key: const ValueKey(
                                              'onboarding_start_listening_btn'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: p.accent,
                                            foregroundColor: p.onAccent,
                                            minimumSize: const Size.fromHeight(
                                              AppSpacing.minTouchTarget,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: AppSpacing.md,
                                              vertical: AppSpacing.xs,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: AppRadii.r16All,
                                            ),
                                            elevation: 2,
                                          ),
                                          onPressed: _isLoading
                                              ? null
                                              : _handleStartListening,
                                          child: _isLoading
                                              ? PulsrProgressBar.circular(
                                                  size: 22,
                                                  strokeWidth: 2.5,
                                                  color: p.onAccent,
                                                )
                                              : Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(
                                                      Icons.play_arrow_rounded,
                                                      size: 22,
                                                    ),
                                                    const SizedBox(
                                                      width: AppSpacing.xs,
                                                    ),
                                                    Flexible(
                                                      child: Text(
                                                        _startListeningLabel(
                                                            context),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: AppFontSize
                                                              .bodyLarge,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        )
                                      : FilledButton.tonal(
                                          key: const ValueKey(
                                              'onboarding_next_btn'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                p.surfaceContainerHigh,
                                            foregroundColor: p.textPrimary,
                                            minimumSize: const Size.fromHeight(
                                              AppSpacing.minTouchTarget,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: AppSpacing.md,
                                              vertical: AppSpacing.xs,
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
                                              Flexible(
                                                child: Text(
                                                  context.l10n.next,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize:
                                                        AppFontSize.bodyLarge,
                                                    fontWeight: FontWeight.w800,
                                                  ),
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

  // ===========================================================================
  // Step 1: Welcome + Storage/Notification Permissions + Live Scanned Counter
  // ===========================================================================
  Widget _buildStep1(BuildContext context) {
    final p = context.palette;
    final isLandscape = context.isLandscape;

    final heroIcon = Container(
      padding: EdgeInsets.all(isLandscape ? 8 : 14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: p.accent.withValues(alpha: 0.18),
        ),
      ),
      child: Container(
        width: isLandscape ? 64 : 88,
        height: isLandscape ? 64 : 88,
        decoration: BoxDecoration(
          color: p.surfaceCard,
          borderRadius: isLandscape ? AppRadii.r20All : AppRadii.r24All,
          border: Border.all(color: p.hairline, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: p.accent.withValues(alpha: 0.22),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: isLandscape ? AppRadii.r20All : AppRadii.r24All,
          child: Image.asset(
            'assets/app_icon/app_icon_plus.png',
            width: isLandscape ? 64 : 88,
            height: isLandscape ? 64 : 88,
            fit: BoxFit.cover,
            semanticLabel: context.l10n.appTitle,
          ),
        ),
      ),
    );

    final headingWidget = Semantics(
      header: true,
      child: Text(
        context.l10n.onboardingHeading,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: AppTracking.heading,
              color: p.textPrimary,
            ),
      ),
    );

    final descWidget = Text(
      context.l10n.onboardingPrivacyDesc,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: p.textSecondary,
            height: 1.45,
          ),
    );

    final permissionsCard = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: AppRadii.r20All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            label: context.l10n.lastScanTracks(_scannedTrackCount),
            child: Container(
              key: const ValueKey('onboarding_live_track_counter'),
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
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.18),
                      borderRadius: AppRadii.r10All,
                    ),
                    child: Icon(
                      _hasScanned
                          ? Icons.library_music_rounded
                          : Icons.radar_rounded,
                      color: p.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.lastScanTracks(_scannedTrackCount),
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.bodySmall,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          _isLoading
                              ? context.l10n.scanningStorage
                              : (_hasScanned
                                  ? context.l10n.scanCompleted
                                  : context.l10n.scanDeviceStorageForAudio),
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color: _hasScanned
                          ? p.success.withValues(alpha: 0.16)
                          : p.surfaceContainerHigh,
                      borderRadius: AppRadii.full,
                    ),
                    child: Text(
                      '$_scannedTrackCount',
                      style: TextStyle(
                        color: _hasScanned ? p.success : p.accent,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading) ...[
            const SizedBox(height: AppSpacing.xs),
            if (_scanProgress != null && _scanProgress! > 0)
              PulsrProgressBar.determinate(
                value: _scanProgress!,
                color: p.accent,
              )
            else
              PulsrProgressBar.indeterminate(color: p.accent),
          ],
          const SizedBox(height: AppSpacing.sm),

          // Primary Storage & Library Scan Permission Action (overflow-safe Row)
          FilledButton.tonal(
            key: const ValueKey('onboarding_step1_grant_access_btn'),
            style: FilledButton.styleFrom(
              backgroundColor: _hasScanned
                  ? p.success.withValues(alpha: 0.16)
                  : p.accent.withValues(alpha: 0.16),
              foregroundColor: _hasScanned ? p.success : p.accent,
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.r14All,
                side: BorderSide(
                  color: (_hasScanned ? p.success : p.accent)
                      .withValues(alpha: 0.35),
                ),
              ),
            ),
            onPressed: _isLoading
                ? null
                : () => _handleGrantAccess(completeOnSuccess: false),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  PulsrProgressBar.circular(
                    size: 18,
                    strokeWidth: 2,
                    color: p.accent,
                  )
                else
                  Icon(
                    _hasScanned
                        ? Icons.check_circle_rounded
                        : Icons.shield_rounded,
                    size: 20,
                  ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    context.l10n.grantAccess,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppFontSize.body,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),

          // Notification Permission Action Row (>= 48dp hit target)
          Semantics(
            button: true,
            toggled: _notificationsGranted,
            label: context.l10n.notificationPermissionTitle,
            child: InkWell(
              key: const ValueKey('onboarding_notification_permission_btn'),
              borderRadius: AppRadii.r14All,
              onTap: _isLoading ? null : _requestNotificationPermission,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.minTouchTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _notificationsGranted
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                        color:
                            _notificationsGranted ? p.success : p.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          context.l10n.notificationPermissionTitle,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        _notificationsGranted
                            ? Icons.check_circle_rounded
                            : Icons.chevron_right_rounded,
                        color:
                            _notificationsGranted ? p.success : p.textTertiary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final privacyBadge = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.15),
              borderRadius: AppRadii.r10All,
            ),
            child: Icon(
              Icons.verified_user_rounded,
              color: p.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              context.l10n.privacyGuarantee,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            maxWidth: PulsrLayoutMetrics.compactDialogMaxWidth),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s28,
            vertical: isLandscape ? AppSpacing.xxs : AppSpacing.sm,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _animateIfEnabled(
                context,
                heroIcon,
                (a) => a.scale(
                  duration: context.motionMs(400),
                  curve: context.motionCurve(Curves.easeOutBack),
                ),
              ),
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.md),
              _animateIfEnabled(
                context,
                headingWidget,
                (a) => a
                    .fadeIn(delay: context.motionMs(120))
                    .slideY(begin: 0.08, end: 0),
              ),
              const SizedBox(height: AppSpacing.xs),
              _animateIfEnabled(
                context,
                descWidget,
                (a) => a
                    .fadeIn(delay: context.motionMs(200))
                    .slideY(begin: 0.08, end: 0),
              ),
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.md),
              _animateIfEnabled(
                context,
                permissionsCard,
                (a) => a.fadeIn(delay: context.motionMs(260)),
              ),
              const SizedBox(height: AppSpacing.xs),
              _animateIfEnabled(
                context,
                privacyBadge,
                (a) => a.fadeIn(delay: context.motionMs(320)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
