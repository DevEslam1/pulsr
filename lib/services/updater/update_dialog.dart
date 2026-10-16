import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/widgets/pulsr_dialog.dart';
import 'app_update_service.dart';

/// Interactive dialog for reviewing and installing app updates.
class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const UpdateDialog({
    super.key,
    required this.info,
  });

  static Future<void> show(BuildContext context, UpdateInfo info) {
    return PulsrDialogHelper.showCustomDialog<void>(
      context,
      barrierDismissible: true,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double _progress = 0.0;
  bool _downloading = false;
  File? _downloadedFile;
  String? _errorMessage;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _errorMessage = null;
      _progress = 0.0;
    });

    try {
      final file = await AppUpdateService.instance.downloadApk(
        widget.info,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadedFile = file;
        });

        // If file downloaded successfully on Android, trigger install automatically
        if (file != null && Platform.isAndroid) {
          await AppUpdateService.instance.installApk(file);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _installDownloaded() async {
    final file = _downloadedFile;
    if (file != null) {
      await AppUpdateService.instance.installApk(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final info = widget.info;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: p.surface,
          borderRadius: AppRadii.r24All,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: AppRadii.r12All,
                      ),
                      child: Icon(
                        Icons.system_update_rounded,
                        color: p.accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Update Available',
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.title,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs,
                                  vertical: AppSpacing.xxs,
                                ),
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(alpha: 0.2),
                                  borderRadius: AppRadii.r6All,
                                ),
                                child: Text(
                                  'v${info.version}',
                                  style: TextStyle(
                                    color: p.accent,
                                    fontSize: AppFontSize.tiny,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                '(Current: v${AppConfig.appVersion})',
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.tiny,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Release notes
                if (info.notes != null && info.notes!.isNotEmpty) ...[
                  Text(
                    "What's New",
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: AppRadii.r12All,
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        info.notes!,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: AppFontSize.bodySmall,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Download Progress
                if (_downloading) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Downloading update...',
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.bodySmall,
                            ),
                          ),
                          Text(
                            '${(_progress * 100).toInt()}%',
                            style: TextStyle(
                              color: p.accent,
                              fontSize: AppFontSize.bodySmall,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ClipRRect(
                        borderRadius: AppRadii.r6All,
                        child: LinearProgressIndicator(
                          value: _progress > 0 ? _progress : null,
                          backgroundColor: p.surfaceContainer,
                          valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Error message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: p.error.withValues(alpha: 0.15),
                      borderRadius: AppRadii.r8All,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: p.error, size: 18),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: p.error,
                              fontSize: AppFontSize.bodySmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        if (_downloading) {
                          AppUpdateService.instance.cancelDownload();
                        }
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        'Later',
                        style: TextStyle(color: p.textSecondary),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (_downloadedFile != null) ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: p.onAccent,
                        ),
                        onPressed: _installDownloaded,
                        icon:
                            const Icon(Icons.install_mobile_rounded, size: 18),
                        label: const Text('Install Now'),
                      ),
                    ] else if (!_downloading) ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: p.onAccent,
                        ),
                        onPressed: _startDownload,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Download & Install'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
