// lib/features/playlists/presentation/widgets/spotify_import_dialog.dart
import 'package:flutter/material.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/errors/error_message_resolver.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../data/services/spotify_importer_service.dart';

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

  Future<void> _startImport() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) return;

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
            context, e.toString().replaceFirst('Exception: ', ''));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return PulsrDialog(
      icon: Icon(
        Icons.playlist_play_rounded,
        size: 30,
        color: p.accent,
      ),
      title: Text(
        _stage == _ImportStage.result
            ? 'Import Complete'
            : 'Import Spotify Playlist',
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
              'Paste a public Spotify playlist link or URI to match and import its tracks into your Pulsr library.',
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.body,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _urlController,
              autofocus: true,
              style:
                  TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
              decoration: InputDecoration(
                hintText: 'https://open.spotify.com/playlist/...',
                hintStyle: TextStyle(
                  color: p.textSecondary.withValues(alpha: 0.6),
                  fontSize: AppFontSize.bodySmall,
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
            ),
          ],
        );

      case _ImportStage.loading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            if (_progressFraction != null) ...[
              LinearProgressIndicator(
                value: _progressFraction,
                backgroundColor: p.surfaceContainer,
                color: p.accent,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${((_progressFraction ?? 0) * 100).toInt()}%',
                style: TextStyle(
                  color: p.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.bodySmall,
                ),
              ),
            ] else ...[
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: p.accent,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              _statusMessage ?? 'Importing playlist...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.body,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        );

      case _ImportStage.result:
        final res = _importResult!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Successfully created playlist "${res.playlistTitle}" with ${res.matchedCount} of ${res.totalTracks} tracks resolved.',
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.body,
                height: 1.45,
              ),
            ),
            if (res.unmatchedTracks.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Unmatched Tracks (${res.unmatchedCount})',
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
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _errorMessage ?? 'An error occurred during import.',
              style: TextStyle(
                color: p.error,
                fontSize: AppFontSize.body,
                height: 1.45,
              ),
            ),
          ],
        );
    }
  }

  List<Widget> _buildActions(BuildContext context, PulsrPalette p) {
    switch (_stage) {
      case _ImportStage.input:
        return [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: Text('Cancel', style: TextStyle(color: p.textSecondary)),
          ),
          FilledButton(
            onPressed: _startImport,
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
            ),
            child: const Text('Import',
                style: TextStyle(fontWeight: FontWeight.w700)),
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
            child: const Text('Done',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ];

      case _ImportStage.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: Text('Cancel', style: TextStyle(color: p.textSecondary)),
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
            child: const Text('Retry',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ];
    }
  }
}
