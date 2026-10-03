import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_empty_state.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../data/scanner/media_scanner_service.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

class EmptyLibrary extends StatefulWidget {
  const EmptyLibrary({super.key});

  @override
  State<EmptyLibrary> createState() => _EmptyLibraryState();
}

class _EmptyLibraryState extends State<EmptyLibrary> {
  bool _isScanning = false;
  bool _hasPermission = true;
  double _scanProgress = 0.0;
  StreamSubscription<double>? _progressSub;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  MediaScannerService? _getScanner() {
    try {
      return context.read<MediaScannerService>();
    } on ProviderNotFoundException catch (_) {
      try {
        if (getIt.isRegistered<MediaScannerService>()) {
          return getIt<MediaScannerService>();
        }
      } catch (e, st) {
        ErrorLogger.log('GetIt lookup for MediaScannerService failed',
            error: e, stackTrace: st, category: 'HomeScreen');
      }
      return null;
    } catch (e, st) {
      ErrorLogger.log(
          'Unexpected error reading MediaScannerService from context',
          error: e,
          stackTrace: st,
          category: 'HomeScreen');
      return null;
    }
  }

  Future<void> _checkPermission() async {
    try {
      final scanner = _getScanner();
      if (scanner == null) return;
      final granted = await scanner.checkPermission();
      if (mounted) setState(() => _hasPermission = granted);
    } catch (e, st) {
      ErrorLogger.log('Failed to check media permission',
          error: e, stackTrace: st, category: 'HomeScreen');
    }
  }

  Future<void> _requestPermission() async {
    final shouldProceed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: context.l10n.homePermissionNeeded,
      message: context.l10n.homePermissionSubtitle,
      confirmLabel: context.l10n.homeGrantPermission,
      cancelLabel: context.l10n.cancel,
      icon: Icons.lock_open_rounded,
    );

    if (shouldProceed != true) return;

    try {
      final scanner = _getScanner();
      if (scanner == null) return;
      final granted = await scanner.requestPermission();
      if (mounted) {
        setState(() => _hasPermission = granted);
        if (granted) {
          _scan();
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to request media permission',
          error: e, stackTrace: st, category: 'HomeScreen');
      if (mounted) {
        setState(() => _hasPermission = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.homePermissionSubtitle)),
        );
      }
    }
  }

  Future<void> _scan() async {
    final scanner = _getScanner();
    if (scanner == null) return;

    setState(() {
      _isScanning = true;
      _scanProgress = 0.0;
    });

    _progressSub?.cancel();
    _progressSub = scanner.scanProgress.listen((p) {
      if (mounted) setState(() => _scanProgress = p);
    });

    try {
      final count = await scanner.scanDeviceLibrary();
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.scanComplete(count)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (!_hasPermission) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.lg, horizontal: AppSpacing.md),
        child: PulsrEmptyState(
          icon: Icons.folder_special_rounded,
          title: context.l10n.homePermissionNeeded,
          subtitle: context.l10n.homePermissionSubtitle,
          primaryActionLabel: context.l10n.homeGrantPermission,
          primaryActionIcon: Icons.lock_open_rounded,
          onPrimaryAction: _requestPermission,
          secondaryActionLabel: context.l10n.hiddenFolders,
          secondaryActionIcon: Icons.folder_off_rounded,
          onSecondaryAction: () => context.push('/hidden-folders'),
        ),
      );
    }

    if (_isScanning) {
      final percent = (_scanProgress * 100).toInt();
      return Padding(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.lg, horizontal: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulsrEmptyState(
              icon: Icons.hourglass_top_rounded,
              title: context.l10n.scanningStorage,
              subtitle: _scanProgress > 0
                  ? context.l10n.homeScanProgress(percent)
                  : context.l10n.homeScanningStorageSubtitle,
              isPrimaryLoading: true,
              primaryActionLabel: context.l10n.homeScanningLabel,
            ),
            if (_scanProgress > 0) ...[
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.r8),
                  child: LinearProgressIndicator(
                    value: _scanProgress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: p.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.lg, horizontal: AppSpacing.md),
      child: PulsrEmptyState(
        icon: Icons.music_off_rounded,
        title: context.l10n.noMusicYet,
        subtitle: context.l10n.scanPrompt,
        primaryActionLabel: context.l10n.scanStorage,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: _scan,
        secondaryActionLabel: context.l10n.hiddenFolders,
        secondaryActionIcon: Icons.folder_off_rounded,
        onSecondaryAction: () => context.push('/hidden-folders'),
      ),
    );
  }
}
