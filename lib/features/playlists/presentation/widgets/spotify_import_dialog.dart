// lib/features/playlists/presentation/widgets/spotify_import_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulsr/core/constants/app_colors.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/errors/error_message_resolver.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../core/widgets/pulsr_progress.dart';
import '../../../../data/services/spotify_importer_service.dart';

import '../../../../core/utils/pulsr_haptics.dart';
/// Modal dialog for importing a Spotify playlist into Pulsr.
class SpotifyImportDialog extends StatefulWidget {
  final VoidCallback? onImportFinished;

  const SpotifyImportDialog({super.key, this.onImportFinished});

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onImportFinished,
  }) {
    return PulsrDialogHelper.showCustomDialog<void>(
      context,
      barrierDismissible: false,
      builder: (_) => SpotifyImportDialog(onImportFinished: onImportFinished),
    );
  }

  @override
  State<SpotifyImportDialog> createState() => _SpotifyImportDialogState();
}

enum _ImportStage { input, loading, result, error }

class _SpotifyImportDialogState extends State<SpotifyImportDialog> {
  final TextEditingController _urlController = TextEditingController();
  _ImportStage _stage = _ImportStage.input;
  String? _statusMessage;
  double? _progressFraction;
  String? _errorMessage;
  SpotifyImportResult? _importResult;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    PulsrHaptics.selectionClick();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty && mounted) {
      _urlController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  Future<void> _startImport() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) return;
    PulsrHaptics.selectionClick();

    final id = SpotifyImporterService.extractPlaylistId(input);
    if (id == null) {
      setState(() {
        _stage = _ImportStage.error;
        _errorMessage =
            'Invalid Spotify playlist URL. Please check the link and try again.';
      });
      return;
    }

    setState(() {
      _stage = _ImportStage.loading;
      _statusMessage = 'Fetching Spotify playlist metadata...';
      _progressFraction = null;
      _errorMessage = null;
    });

    try {
      final importer = getIt.isRegistered<SpotifyImporterService>()
          ? getIt<SpotifyImporterService>()
          : SpotifyImporterService();

      final result = await importer.importPlaylist(
        input,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            _statusMessage =
                'Matching tracks on YouTube Music ($completed/$total)...';
            _progressFraction = total > 0 ? completed / total : null;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _stage = _ImportStage.result;
        _importResult = result;
      });
      widget.onImportFinished?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _ImportStage.error;
        _errorMessage = resolveUiErrorMessage(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return PulsrDialog(
      icon: Container(
        padding: const EdgeInsets.all(AppSpacing.s10),
        decoration: BoxDecoration(
          color: AppColors.spotifyGreen.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _stage == _ImportStage.result
              ? Icons.check_circle_rounded
              : (_stage == _ImportStage.error
                  ? Icons.error_outline_rounded
                  : Icons.playlist_play_rounded),
          size: 28,
          color:
              _stage == _ImportStage.error ? p.error : AppColors.spotifyGreen,
        ),
      ),
      title: Text(
        _stage == _ImportStage.result
            ? 'Import Complete'
            : context.l10n.playlistImportSpotify,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: AppFontSize.title,
        ),
      ),
      content: _buildContent(context, p),
      actions: _buildActions(context, p),
    );
  }

  Widget _buildContent(BuildContext context, PulsrPalette p) {
    switch (_stage) {
      case _ImportStage.input:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.spotifyImportHelp,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.body,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _urlController,
              builder: (context, value, _) {
                final hasText = value.text.isNotEmpty;
                return TextField(
                  controller: _urlController,
                  autofocus: true,
                  autocorrect: false,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'https://open.spotify.com/playlist/...',
                    hintStyle: TextStyle(
                      color: p.textSecondary.withValues(alpha: 0.6),
                      fontSize: AppFontSize.bodySmall,
                    ),
                    prefixIcon: Icon(
                      Icons.link_rounded,
                      size: 20,
                      color: hasText ? AppColors.spotifyGreen : p.textTertiary,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        hasText
                            ? Icons.close_rounded
                            : Icons.content_paste_rounded,
                        size: 18,
                        color: p.textSecondary,
                      ),
                      tooltip: hasText ? context.l10n.clear : 'Paste',
                      onPressed: () {
                        if (hasText) {
                          _urlController.clear();
                        } else {
                          _pasteFromClipboard();
                        }
                      },
                    ),
                    filled: true,
                    fillColor: p.surfaceContainer,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.r12All,
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadii.r12All,
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppRadii.r12All,
                      borderSide: BorderSide(color: p.accent, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _startImport(),
                );
              },
            ),
          ],
        );

      case _ImportStage.loading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.xs),
            if (_progressFraction != null) ...[
              PulsrProgressBar.determinate(
                value: _progressFraction!,
                height: 6,
                color: p.accent,
                backgroundColor: p.surfaceContainer,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${((_progressFraction ?? 0) * 100).toInt()}%',
                style: TextStyle(
                  color: p.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: AppFontSize.bodySmall,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ] else ...[
              PulsrProgressBar.circular(
                size: 30,
                strokeWidth: 3,
                color: p.accent,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              _statusMessage ?? context.l10n.spotifyImporting,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.body,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        );

      case _ImportStage.result:
        final res = _importResult!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: p.surfaceContainer,
                borderRadius: AppRadii.r12All,
                border: Border.all(color: p.hairline),
              ),
              child: Text(
                'Successfully created playlist "${res.playlistTitle}" with ${res.matchedCount} of ${res.totalTracks} tracks resolved.',
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.bodySmall,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            if (res.unmatchedTracks.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.spotifyUnmatchedTracks(res.unmatchedCount),
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.bodySmall,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: AppRadii.r12All,
                  border: Border.all(color: p.hairline),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  itemCount: res.unmatchedTracks.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: p.hairline),
                  itemBuilder: (context, i) {
                    final t = res.unmatchedTracks[i];
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Text(
                        t.artist.isNotEmpty
                            ? '${t.title} · ${t.artist}'
                            : t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.caption,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        );

      case _ImportStage.error:
        return Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: p.error.withValues(alpha: 0.10),
            borderRadius: AppRadii.r12All,
            border: Border.all(color: p.error.withValues(alpha: 0.32)),
          ),
          child: Text(
            _errorMessage ?? context.l10n.spotifyImportFailed,
            style: TextStyle(
              color: p.error,
              fontSize: AppFontSize.bodySmall,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        );
    }
  }

  List<Widget> _buildActions(BuildContext context, PulsrPalette p) {
    switch (_stage) {
      case _ImportStage.input:
        return [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: Text(
              context.l10n.cancel,
              style: TextStyle(color: p.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: _startImport,
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
            ),
            child: Text(
              context.l10n.importAction,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ];

      case _ImportStage.loading:
        return const [];

      case _ImportStage.result:
        return [
          FilledButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
            ),
            child: Text(
              context.l10n.done,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ];

      case _ImportStage.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: Text(
              context.l10n.cancel,
              style: TextStyle(color: p.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _stage = _ImportStage.input;
              });
            },
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
            ),
            child: Text(
              context.l10n.retry,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ];
    }
  }
}
