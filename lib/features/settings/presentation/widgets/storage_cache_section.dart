// lib/features/settings/presentation/widgets/storage_cache_section.dart
import 'package:flutter/material.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/artwork_cache_manager.dart';
import '../../../../core/services/ytm_cache_manager.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';

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
    if (mounted) {
      setState(() {
        _artCacheSizeBytes = artSize;
        _streamCacheSizeBytes = streamSize;
        _isLoading = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final manager = ArtworkCacheManager();
    final maxMb = manager.maxCacheSizeMb;

    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: p.accentContainer,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.photo_size_select_actual_rounded,
                color: p.accent, size: 20),
          ),
          title: Text(
            context.l10n.artworkCache,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Text(
            _isLoading
                ? context.l10n.calculating
                : context.l10n.cacheUsedOfMax(
                    _formatSize(_artCacheSizeBytes), maxMb),
            style: TextStyle(color: p.textSecondary, fontSize: 12),
          ),
          trailing: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: p.error,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(context.l10n.clear),
            onPressed: () async {
              await manager.clearAllCache();
              await _refreshCacheSize();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(context.l10n.artworkCacheCleared)),
                );
              }
            },
          ),
        ),
        Divider(height: 1, indent: 68, color: p.hairline),
        if (AppConfig.ytmEnabled) ...[
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: p.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.cloud_download_rounded,
                  color: p.error, size: 20),
            ),
            title: Text(
              context.l10n.youtubeStreamDiskCache,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: Text(
              _isLoading
                  ? context.l10n.calculating
                  : context.l10n.streamCacheCachedForReplay(
                      _formatSize(_streamCacheSizeBytes)),
              style: TextStyle(color: p.textSecondary, fontSize: 12),
            ),
            trailing: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: p.error,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(context.l10n.clear),
              onPressed: () async {
                final cacheManager = _ytmCacheManager;
                if (cacheManager == null) return;
                await cacheManager.clearCache();
                await _refreshCacheSize();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(context.l10n.streamCacheCleared)),
                  );
                }
              },
            ),
          ),
          Divider(height: 1, indent: 68, color: p.hairline),
        ],
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: p.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(11),
            ),
            child:
                Icon(Icons.disc_full_rounded, color: p.textSecondary, size: 20),
          ),
          title: Text(
            context.l10n.maximumArtworkCacheLimit,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Text(
            context.l10n.maxMbAutoEvicts(maxMb),
            style: TextStyle(color: p.textSecondary, fontSize: 12),
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

    showModalBottomSheet(
      context: context,
      backgroundColor: p.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    context.l10n.maximumArtworkCacheLimit,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...options.map((limit) {
                  final isSelected = manager.maxCacheSizeMb == limit;
                  return ListTile(
                    title: Text(
                      context.l10n.mbValue(limit),
                      style: TextStyle(
                        color: isSelected ? p.accent : p.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
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
