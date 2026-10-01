import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/artwork_cache_manager.dart';
import '../../../../core/services/ytm_cache_manager.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// Storage & Cache section widget: displays album artwork cache size,
/// YouTube stream cache size (if YTM enabled), cache clearing affordances,
/// and artwork disk cache size limits.
class StorageCacheSection extends StatefulWidget {
  const StorageCacheSection({super.key});

  @override
  State<StorageCacheSection> createState() => _StorageCacheSectionState();
}

class _StorageCacheSectionState extends State<StorageCacheSection>
    with WidgetsBindingObserver {
  int _artCacheSizeBytes = 0;
  int _streamCacheSizeBytes = 0;
  int _lyricsCacheSizeBytes = 0;
  int _tempCacheSizeBytes = 0;
  bool _isLoading = true;

  YtmCacheManager? get _ytmCacheManager =>
      AppConfig.ytmEnabled && getIt.isRegistered<YtmCacheManager>()
          ? getIt<YtmCacheManager>()
          : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshCacheSize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshCacheSize();
    }
  }

  Future<void> _refreshCacheSize() async {
    final artSize = await ArtworkCacheManager().getDiskCacheSizeBytes();
    final cacheManager = _ytmCacheManager;
    final streamSize =
        cacheManager == null ? 0 : await cacheManager.getCacheSizeBytes();
    int lyricsSize = 0;
    int tempSize = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity
            in tempDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              final len = await entity.length();
              final path = entity.path.toLowerCase();
              if (path.endsWith('.lrc') || path.contains('lyrics')) {
                lyricsSize += len;
              } else if (!path.contains('artwork') && !path.contains('ytm')) {
                tempSize += len;
              }
            } catch (e, st) {
              ErrorLogger.log('Storage file length check failed',
                  error: e, stackTrace: st, category: 'Storage');
            }
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Storage tempDir scan failed',
          error: e, stackTrace: st, category: 'Storage');
    }

    if (mounted) {
      setState(() {
        _artCacheSizeBytes = artSize;
        _streamCacheSizeBytes = streamSize;
        _lyricsCacheSizeBytes = lyricsSize;
        _tempCacheSizeBytes = tempSize;
        _isLoading = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required BuildContext context,
  }) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.s6),
        Text(
          label,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: p.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownBar(BuildContext context) {
    final p = context.palette;
    final totalBytes = _artCacheSizeBytes +
        _streamCacheSizeBytes +
        _lyricsCacheSizeBytes +
        _tempCacheSizeBytes;

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainerHigh.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadii.r16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.l10n.storageBreakdown,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.body,
                  color: p.textPrimary,
                ),
              ),
              Text(
                _isLoading ? '...' : _formatSize(totalBytes),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.label,
                  color: p.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.r6),
            child: SizedBox(
              height: 10,
              child: totalBytes == 0 || _isLoading
                  ? Container(color: p.surfaceContainerHigh)
                  : Row(
                      children: [
                        if (_artCacheSizeBytes > 0)
                          Expanded(
                            flex: _artCacheSizeBytes,
                            child: Container(color: p.accent),
                          ),
                        if (_streamCacheSizeBytes > 0)
                          Expanded(
                            flex: _streamCacheSizeBytes,
                            child: Container(color: p.error),
                          ),
                        if (_lyricsCacheSizeBytes > 0)
                          Expanded(
                            flex: _lyricsCacheSizeBytes,
                            child: Container(color: AppColors.cacheLyrics),
                          ),
                        if (_tempCacheSizeBytes > 0)
                          Expanded(
                            flex: _tempCacheSizeBytes,
                            child: Container(color: p.textTertiary),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _buildLegendItem(
                color: p.accent,
                label: context.l10n
                    .storageLegendArtwork(_formatSize(_artCacheSizeBytes)),
                context: context,
              ),
              if (AppConfig.ytmEnabled && _streamCacheSizeBytes > 0)
                _buildLegendItem(
                  color: p.error,
                  label: context.l10n
                      .storageLegendStreams(_formatSize(_streamCacheSizeBytes)),
                  context: context,
                ),
              _buildLegendItem(
                color: AppColors.cacheLyrics,
                label: context.l10n
                    .storageLegendLyrics(_formatSize(_lyricsCacheSizeBytes)),
                context: context,
              ),
              _buildLegendItem(
                color: p.textTertiary,
                label: context.l10n
                    .storageLegendCacheDb(_formatSize(_tempCacheSizeBytes)),
                context: context,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final manager = ArtworkCacheManager();
    final maxMb = manager.maxCacheSizeMb;

    return Column(
      children: [
        _buildBreakdownBar(context),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: p.accentContainer,
              borderRadius: BorderRadius.circular(AppRadii.r12),
            ),
            child: Icon(Icons.photo_size_select_actual_rounded,
                color: p.accent, size: 20),
          ),
          title: Text(
            context.l10n.artworkCache,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: AppFontSize.body),
          ),
          subtitle: Text(
            _isLoading
                ? context.l10n.calculating
                : context.l10n
                    .cacheUsedOfMax(_formatSize(_artCacheSizeBytes), maxMb),
            style:
                TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
          ),
          trailing: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: p.error,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(context.l10n.clear),
            onPressed: () async {
              final confirmed = await PulsrDialogHelper.showConfirmDialog(
                context,
                title: context.l10n.clear,
                message: context.l10n.confirm,
                confirmLabel: context.l10n.clear,
                isDestructive: true,
              );
              if (confirmed != true) return;
              await manager.clearAllCache();
              await _refreshCacheSize();
              if (context.mounted) {
                PulsrToast.show(
                  context,
                  message: context.l10n.artworkCacheCleared,
                  isSuccess: true,
                );
              }
            },
          ),
        ),
        Divider(height: 1, indent: 68, color: p.hairline),
        if (AppConfig.ytmEnabled) ...[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: p.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadii.r12),
              ),
              child:
                  Icon(Icons.cloud_download_rounded, color: p.error, size: 20),
            ),
            title: Text(
              context.l10n.youtubeStreamDiskCache,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: AppFontSize.body),
            ),
            subtitle: Text(
              _isLoading
                  ? context.l10n.calculating
                  : context.l10n.streamCacheCachedForReplay(
                      _formatSize(_streamCacheSizeBytes)),
              style: TextStyle(
                  color: p.textSecondary, fontSize: AppFontSize.label),
            ),
            trailing: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: p.error,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(context.l10n.clear),
              onPressed: () async {
                final confirmed = await PulsrDialogHelper.showConfirmDialog(
                  context,
                  title: context.l10n.clear,
                  message: context.l10n.confirm,
                  confirmLabel: context.l10n.clear,
                  isDestructive: true,
                );
                if (confirmed != true) return;
                final cacheManager = _ytmCacheManager;
                if (cacheManager == null) return;
                await cacheManager.clearCache();
                await _refreshCacheSize();
                if (context.mounted) {
                  PulsrToast.show(
                    context,
                    message: context.l10n.streamCacheCleared,
                    isSuccess: true,
                  );
                }
              },
            ),
          ),
          Divider(height: 1, indent: 68, color: p.hairline),
        ],
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: p.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadii.r12),
            ),
            child:
                Icon(Icons.disc_full_rounded, color: p.textSecondary, size: 20),
          ),
          title: Text(
            context.l10n.maximumArtworkCacheLimit,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: AppFontSize.body),
          ),
          subtitle: Text(
            context.l10n.maxMbAutoEvicts(maxMb),
            style:
                TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
          ),
          trailing: Icon(Icons.chevron_right_rounded,
              size: 20, color: p.textTertiary),
          onTap: () => _showMaxCacheLimitPicker(context, manager),
        ),
      ],
    );
  }

  void _showMaxCacheLimitPicker(
      BuildContext context, ArtworkCacheManager manager) {
    final p = context.palette;
    final options = [50, 100, 250, 500];

    PulsrSheetHelper.showPulsrSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
                  child: Text(
                    context.l10n.maximumArtworkCacheLimit,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: AppFontSize.title,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...options.map((limit) {
                  final isSelected = manager.maxCacheSizeMb == limit;
                  return ListTile(
                    title: Text(
                      context.l10n.mbValue(limit),
                      style: TextStyle(
                        color: isSelected ? p.accent : p.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: p.accent)
                        : null,
                    onTap: () async {
                      await manager.setMaxCacheSizeMb(limit);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _refreshCacheSize();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
