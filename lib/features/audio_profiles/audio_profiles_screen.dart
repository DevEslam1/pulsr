// lib/features/audio_profiles/audio_profiles_screen.dart
//
// Capture, apply, share, import and delete shareable audio profiles. The
// screen owns dialogs, list state and accessibility labels; the service owns
// the files and every write to the live audio settings.

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/errors/app_error.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/error_logger.dart';
import '../../core/widgets/pulsr_dialog.dart';
import '../../core/widgets/pulsr_empty_state.dart';
import '../../core/widgets/pulsr_progress.dart';
import 'audio_profile.dart';
import 'audio_profile_service.dart';
import 'audio_profile_strings.dart';

/// Lists the saved audio profiles and lets the user capture the current setup,
/// apply a profile with automatic backup, share one, import a `.json` file and
/// delete what is no longer needed.
class AudioProfilesScreen extends StatefulWidget {
  const AudioProfilesScreen({
    super.key,
    required this.service,
    this.deviceLabel,
  });

  /// Store and applier for the profiles.
  final AudioProfileService service;

  /// Label of the currently connected output device, injected so the screen
  /// stays independent of the audio stack.
  final String? Function()? deviceLabel;

  @override
  State<AudioProfilesScreen> createState() => _AudioProfilesScreenState();
}

class _AudioProfilesScreenState extends State<AudioProfilesScreen> {
  List<AudioProfile> _profiles = const <AudioProfile>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final profiles = await widget.service.list();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _loading = false;
        _error = null;
      });
    } catch (e, st) {
      ErrorLogger.log(
        'Loading audio profiles failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfilesScreen',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            e is AppError ? e.userMessage : AudioProfileStrings.errorSubtitle;
      });
    }
  }

  Future<void> _runAction(
    Future<String?> Function() action, {
    required String failureMessage,
  }) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errorColor = context.palette.error;
    setState(() => _busy = true);
    try {
      final message = await action();
      await _load(showSpinner: false);
      if (!mounted) return;
      if (message != null) {
        messenger?.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e, st) {
      ErrorLogger.log(
        failureMessage,
        error: e,
        stackTrace: st,
        category: 'AudioProfilesScreen',
      );
      if (!mounted) return;
      final text = e is AppError ? e.userMessage : failureMessage;
      messenger?.showSnackBar(
        SnackBar(content: Text(text), backgroundColor: errorColor),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _captureCurrent() async {
    final name = await PulsrDialogHelper.showInputDialog(
      context,
      title: AudioProfileStrings.captureDialogTitle,
      message: AudioProfileStrings.captureDialogMessage,
      hintText: AudioProfileStrings.captureDialogHint,
      icon: Icons.tune_rounded,
      confirmLabel: AudioProfileStrings.captureConfirm,
    );
    if (!mounted || name == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text(AudioProfileStrings.nameRequired)),
      );
      return;
    }
    final device = widget.deviceLabel?.call();
    await _runAction(
      () async {
        await widget.service.captureCurrent(trimmed, deviceName: device);
        return AudioProfileStrings.captureSaved;
      },
      failureMessage: AudioProfileStrings.captureFailed,
    );
  }

  Future<void> _apply(AudioProfile profile) async {
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: AudioProfileStrings.applyDialogTitle,
      message: AudioProfileStrings.applyDialogBody(profile.name),
      confirmLabel: AudioProfileStrings.applyConfirm,
      icon: Icons.restore_rounded,
    );
    if (!mounted || confirmed != true) return;
    await _runAction(
      () async {
        final report = await widget.service.apply(profile);
        return AudioProfileStrings.applyDone(report.appliedCount);
      },
      failureMessage: AudioProfileStrings.applyFailed,
    );
  }

  Future<void> _delete(AudioProfile profile) async {
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: AudioProfileStrings.deleteDialogTitle,
      message: AudioProfileStrings.deleteDialogBody(profile.name),
      confirmLabel: AudioProfileStrings.deleteConfirm,
      isDestructive: true,
    );
    if (!mounted || confirmed != true) return;
    await _runAction(
      () async {
        await widget.service.delete(profile.id);
        return AudioProfileStrings.deleted;
      },
      failureMessage: AudioProfileStrings.deleteFailed,
    );
  }

  Future<void> _share(AudioProfile profile) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errorColor = context.palette.error;
    try {
      final file = await widget.service.export(profile);
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(file.path, mimeType: 'application/json'),
          ],
          text: AudioProfileStrings.shareText(profile.name),
        ),
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Sharing audio profile failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfilesScreen',
      );
      messenger?.showSnackBar(
        SnackBar(
          content: const Text(AudioProfileStrings.shareFailed),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final path = await _pickJsonPath(messenger);
    if (path == null) return;
    await _runAction(
      () async {
        await widget.service.importFromFile(path);
        return AudioProfileStrings.importSaved;
      },
      failureMessage: AudioProfileStrings.importFailed,
    );
  }

  Future<String?> _pickJsonPath(ScaffoldMessengerState? messenger) async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
      );
      return picked?.path;
    } catch (e, st) {
      ErrorLogger.log(
        'Picking a profile file failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfilesScreen',
      );
      messenger?.showSnackBar(
        const SnackBar(content: Text(AudioProfileStrings.importFailed)),
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AudioProfileStrings.screenTitle),
        actions: <Widget>[
          IconButton(
            tooltip: AudioProfileStrings.refreshTooltip,
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(
              deviceLabel: widget.deviceLabel,
              busy: _busy,
              onCapture: _captureCurrent,
              onImport: _import,
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(width: 160, child: PulsrProgressBar()),
      );
    }
    if (_error != null) {
      return PulsrEmptyState(
        icon: Icons.error_outline_rounded,
        title: AudioProfileStrings.errorTitle,
        subtitle: _error!,
        primaryActionLabel: AudioProfileStrings.retry,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: () => _load(),
      );
    }
    if (_profiles.isEmpty) {
      return PulsrEmptyState(
        icon: Icons.tune_rounded,
        title: AudioProfileStrings.emptyTitle,
        subtitle: AudioProfileStrings.emptySubtitle,
        primaryActionLabel: AudioProfileStrings.captureAction,
        primaryActionIcon: Icons.add_rounded,
        onPrimaryAction: _captureCurrent,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      itemCount: _profiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final profile = _profiles[index];
        return _ProfileCard(
          profile: profile,
          busy: _busy,
          onApply: () => _apply(profile),
          onShare: () => _share(profile),
          onDelete: () => _delete(profile),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.deviceLabel,
    required this.busy,
    required this.onCapture,
    required this.onImport,
  });

  final String? Function()? deviceLabel;
  final bool busy;
  final VoidCallback onCapture;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final device = deviceLabel?.call();
    final label = device == null || device.trim().isEmpty
        ? AudioProfileStrings.deviceUnknown
        : device;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.speaker_rounded, size: 20, color: p.accent),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        AudioProfileStrings.deviceLabelPrefix,
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          color: p.textTertiary,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.bodySmall,
                          color: p.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: _A11yButton(
                  label: AudioProfileStrings.captureAction,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onCapture,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text(AudioProfileStrings.captureAction),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _A11yButton(
                  label: AudioProfileStrings.importAction,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onImport,
                    icon: const Icon(Icons.file_open_rounded),
                    label: const Text(AudioProfileStrings.importAction),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.busy,
    required this.onApply,
    required this.onShare,
    required this.onDelete,
  });

  final AudioProfile profile;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final meta = <String>[
      if (profile.deviceName != null && profile.deviceName!.trim().isNotEmpty)
        profile.deviceName!,
      _formatDate(profile.createdAt),
      'v${profile.appVersion}',
    ].join(' - ');
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            profile.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.bodyLarge,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            AudioProfileStrings.profileSummary(profile.valueCount),
            style: TextStyle(
              fontSize: AppFontSize.bodySmall,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: p.textTertiary,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              _A11yButton(
                label: AudioProfileStrings.applyTooltip,
                child: IconButton(
                  tooltip: AudioProfileStrings.applyTooltip,
                  onPressed: busy ? null : onApply,
                  icon: Icon(
                    Icons.play_circle_outline_rounded,
                    color: p.accent,
                  ),
                ),
              ),
              _A11yButton(
                label: AudioProfileStrings.shareTooltip,
                child: IconButton(
                  tooltip: AudioProfileStrings.shareTooltip,
                  onPressed: busy ? null : onShare,
                  icon: Icon(Icons.ios_share_rounded, color: p.textSecondary),
                ),
              ),
              _A11yButton(
                label: AudioProfileStrings.deleteTooltip,
                child: IconButton(
                  tooltip: AudioProfileStrings.deleteTooltip,
                  onPressed: busy ? null : onDelete,
                  icon: Icon(Icons.delete_outline_rounded, color: p.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Exposes one explicit accessibility label per control.
class _A11yButton extends StatelessWidget {
  const _A11yButton({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: child,
    );
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
