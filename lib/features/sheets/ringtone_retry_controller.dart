// lib/features/sheets/ringtone_retry_controller.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/channels.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/widgets/pulsr_bottom_sheet.dart';
import '../../core/widgets/pulsr_dialog.dart';
import '../../l10n/generated/app_localizations.dart';
import '../library/cubit/library_cubit.dart';
import '../player/cubit/player_cubit.dart';
import '../ytm_search/cubit/ytm_download_cubit.dart';

/// Parent/navigator/cubit handles captured from a bottom sheet context BEFORE
/// [Navigator.pop] so async or deferred actions survive the sheet's unmount.
class CapturedSheetContext {
  final BuildContext? parentContext;
  final BuildContext sheetContext;
  final NavigatorState? navigator;
  final NavigatorState? rootNavigator;
  final ScaffoldMessengerState? messenger;
  final GoRouter? router;
  final AppLocalizations l10n;
  final PulsrPalette palette;
  final PlayerCubit? playerCubit;
  final LibraryCubit? libraryCubit;
  final YtmDownloadCubit? downloadCubit;

  const CapturedSheetContext._({
    required this.parentContext,
    required this.sheetContext,
    required this.navigator,
    required this.rootNavigator,
    required this.messenger,
    required this.router,
    required this.l10n,
    required this.palette,
    required this.playerCubit,
    required this.libraryCubit,
    required this.downloadCubit,
  });

  /// Captures navigation, messenger, theme, l10n, and cubits while
  /// [sheetContext] is still mounted.
  factory CapturedSheetContext.capture(
    BuildContext sheetContext, {
    BuildContext? parentContext,
  }) {
    PlayerCubit? playerCubit;
    LibraryCubit? libraryCubit;
    YtmDownloadCubit? downloadCubit;
    try {
      playerCubit = sheetContext.read<PlayerCubit?>();
    } catch (_) {}
    try {
      libraryCubit = sheetContext.read<LibraryCubit?>();
    } catch (_) {}
    try {
      downloadCubit = sheetContext.read<YtmDownloadCubit?>();
    } catch (_) {}

    return CapturedSheetContext._(
      parentContext: parentContext,
      sheetContext: sheetContext,
      navigator: Navigator.maybeOf(sheetContext),
      rootNavigator: Navigator.maybeOf(sheetContext, rootNavigator: true),
      messenger: ScaffoldMessenger.maybeOf(sheetContext),
      router: GoRouter.maybeOf(sheetContext),
      l10n: sheetContext.l10n,
      palette: sheetContext.palette,
      playerCubit: playerCubit,
      libraryCubit: libraryCubit,
      downloadCubit: downloadCubit,
    );
  }

  /// Resolves a still-mounted [BuildContext] that outlives the popped sheet.
  BuildContext? get liveHostContext {
    final parent = parentContext;
    if (parent != null && parent.mounted) return parent;
    final rootKeyCtx = rootNavigatorKey.currentContext;
    if (rootKeyCtx != null && rootKeyCtx.mounted) return rootKeyCtx;
    final rootOverlayCtx = rootNavigator?.overlay?.context;
    if (rootOverlayCtx != null && rootOverlayCtx.mounted) {
      return rootOverlayCtx;
    }
    final navOverlayCtx = navigator?.overlay?.context;
    if (navOverlayCtx != null && navOverlayCtx.mounted) return navOverlayCtx;
    if (sheetContext.mounted) return sheetContext;
    return null;
  }

  /// Resolves a live [ScaffoldMessengerState] using the pre-popped messenger
  /// first and falling back to [liveHostContext].
  ScaffoldMessengerState? get liveMessenger {
    final captured = messenger;
    if (captured != null && captured.mounted) return captured;
    final host = liveHostContext;
    return host != null ? ScaffoldMessenger.maybeOf(host) : null;
  }

  /// Pops the sheet route when it can be popped.
  void popSheet() {
    final nav = navigator;
    if (nav != null && nav.canPop()) {
      nav.pop();
    }
  }

  /// Shows [snackBar] via the surviving [liveMessenger].
  void showSnackBar(SnackBar snackBar) {
    final m = liveMessenger;
    if (m == null) return;
    m
      ..clearSnackBars()
      ..showSnackBar(snackBar);
  }

  /// Pushes a GoRouter destination even after the sheet has popped.
  void pushRoute(String location, {Object? extra}) {
    if (router != null) {
      router!.push(location, extra: extra);
      return;
    }
    final host = liveHostContext;
    if (host != null) {
      GoRouter.maybeOf(host)?.push(location, extra: extra);
    }
  }
}

/// App/route-scoped controller for Android `WRITE_SETTINGS` ringtone retry.
///
/// Holding the [AppLifecycleListener] here rather than on a bottom-sheet `State`
/// ensures returning from Android Settings still retries [setRingtone] even
/// when the originating sheet has already been popped or disposed.
class RingtoneRetryController {
  RingtoneRetryController._();

  static AppLifecycleListener? _activeListener;

  @visibleForTesting
  static bool get hasPendingListener => _activeListener != null;

  @visibleForTesting
  static void resetForTesting() {
    _activeListener?.dispose();
    _activeListener = null;
  }

  /// Displays the "Set Audio As" ringtone type picker sheet and routes the
  /// chosen type to [setRingtone].
  static void showOptionsSheet({
    required BuildContext hostContext,
    required String songPath,
    ScaffoldMessengerState? messenger,
    AppLocalizations? l10n,
  }) {
    final p = hostContext.palette;
    final strings = l10n ?? hostContext.l10n;
    final capturedMessenger =
        messenger ?? ScaffoldMessenger.maybeOf(hostContext);
    PulsrSheetHelper.showPulsrSheet(
      context: hostContext,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                strings.setAudioAs,
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                    ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            ListTile(
              leading: Icon(Icons.ring_volume_rounded, color: p.accent),
              title: Text(strings.phoneRingtone,
                  style: TextStyle(color: p.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setRingtone(
                  songPath: songPath,
                  type: 'ringtone',
                  l10n: strings,
                  messenger: capturedMessenger,
                  dialogContext: hostContext,
                );
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.notifications_active_rounded, color: p.accent),
              title: Text(strings.notificationSound,
                  style: TextStyle(color: p.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setRingtone(
                  songPath: songPath,
                  type: 'notification',
                  l10n: strings,
                  messenger: capturedMessenger,
                  dialogContext: hostContext,
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.alarm_rounded, color: p.accent),
              title: Text(strings.alarmSound,
                  style: TextStyle(color: p.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setRingtone(
                  songPath: songPath,
                  type: 'alarm',
                  l10n: strings,
                  messenger: capturedMessenger,
                  dialogContext: hostContext,
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        );
      },
    );
  }

  /// Sets [songPath] as the system ringtone/notification/alarm sound, prompting
  /// for Android `WRITE_SETTINGS` permission and listening across lifecycle
  /// resume when permission is missing.
  static Future<void> setRingtone({
    required String songPath,
    required String type,
    required AppLocalizations l10n,
    ScaffoldMessengerState? messenger,
    BuildContext? dialogContext,
  }) async {
    const channel = MethodChannel(PulsrChannels.ringtone);
    final label = type == 'notification'
        ? l10n.browseNotificationSound
        : type == 'alarm'
            ? l10n.browseAlarmSound
            : l10n.ringtone;

    void showSnack(SnackBar bar) {
      final liveCtx = rootNavigatorKey.currentContext;
      final activeMessenger = (messenger != null && messenger.mounted)
          ? messenger
          : (dialogContext != null && dialogContext.mounted
              ? ScaffoldMessenger.maybeOf(dialogContext)
              : (liveCtx != null && liveCtx.mounted
                  ? ScaffoldMessenger.maybeOf(liveCtx)
                  : null));
      if (activeMessenger == null) return;
      activeMessenger
        ..clearSnackBars()
        ..showSnackBar(bar);
    }

    try {
      if (Platform.isAndroid) {
        final canWrite =
            await channel.invokeMethod<bool>('checkWriteSettingsPermission') ??
                true;
        if (!canWrite) {
          final ctx = (dialogContext != null && dialogContext.mounted)
              ? dialogContext
              : rootNavigatorKey.currentContext;
          if (ctx == null || !ctx.mounted) return;
          final proceed = await PulsrDialogHelper.showConfirmDialog(
            ctx,
            title: l10n.permissionRequired,
            message:
                '${l10n.browseToSet} $label ${l10n.browseRequiresModifySettings}',
            icon: Icons.security_rounded,
            confirmLabel: l10n.openSettings,
            cancelLabel: l10n.cancel,
          );
          if (proceed == true) {
            openSettingsAndListenForRetry(
              songPath: songPath,
              channel: channel,
              type: type,
              l10n: l10n,
              messenger: messenger,
            );
          }
          return;
        }
      }

      final success = await channel.invokeMethod<bool>('setRingtone', {
        'filePath': songPath,
        'type': type,
      });
      if (success ?? false) {
        showSnack(SnackBar(content: Text(l10n.ringtoneSet)));
      } else {
        showSnack(SnackBar(content: Text(l10n.ringtoneFailed)));
      }
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        showSnack(
          SnackBar(
            content: Text(l10n.ringtoneFailed),
            action: SnackBarAction(
              label: l10n.settings,
              onPressed: () {
                openSettingsAndListenForRetry(
                  songPath: songPath,
                  channel: channel,
                  type: type,
                  l10n: l10n,
                  messenger: messenger,
                );
              },
            ),
          ),
        );
      } else {
        showSnack(
          SnackBar(content: Text('${l10n.ringtoneFailed} ${e.message}')),
        );
      }
    } catch (e) {
      showSnack(SnackBar(content: Text('${l10n.ringtoneFailed} $e')));
    }
  }

  static Future<void> _completeRetryFromRoot({
    required String songPath,
    required String type,
    required AppLocalizations l10n,
    required ScaffoldMessengerState? fallbackMessenger,
  }) {
    final activeContext = rootNavigatorKey.currentContext;
    final mountedContext =
        (activeContext != null && activeContext.mounted) ? activeContext : null;
    final activeMessenger = mountedContext != null
        ? ScaffoldMessenger.maybeOf(mountedContext)
        : fallbackMessenger;
    return setRingtone(
      songPath: songPath,
      type: type,
      l10n: l10n,
      messenger: activeMessenger,
      dialogContext: mountedContext,
    );
  }

  /// Opens Android `WRITE_SETTINGS` and attaches an app-scoped resume listener
  /// to automatically complete setting [type] when the user grants access.
  static void openSettingsAndListenForRetry({
    required String songPath,
    required MethodChannel channel,
    required String type,
    required AppLocalizations l10n,
    ScaffoldMessengerState? messenger,
  }) {
    _activeListener?.dispose();
    _activeListener = AppLifecycleListener(
      onResume: () async {
        final listener = _activeListener;
        _activeListener = null;
        listener?.dispose();
        try {
          final canWrite = await channel
                  .invokeMethod<bool>('checkWriteSettingsPermission') ??
              false;
          if (!canWrite) return;
          await _completeRetryFromRoot(
            songPath: songPath,
            type: type,
            l10n: l10n,
            fallbackMessenger: messenger,
          );
        } catch (e, st) {
          ErrorLogger.log(
            'Auto-retry setRingtone failed after returning from settings',
            error: e,
            stackTrace: st,
            category: 'RingtoneRetryController',
          );
        }
      },
    );
    channel.invokeMethod('openWriteSettings');
  }
}
