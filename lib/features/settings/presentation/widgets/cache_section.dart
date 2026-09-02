// lib/features/settings/presentation/widgets/cache_section.dart
import 'package:flutter/material.dart';
import '../../../../data/services/artwork_cache_manager.dart';
import '../../../../data/services/ytm_cache_manager.dart';
import '../../../../core/theme/aura_theme.dart';

/// Storage & cache rows: artwork cache, YouTube stream cache, max cache limit.
/// Moved verbatim from settings_screen.dart (was `_CacheSection`).
class CacheSection extends StatefulWidget {
  const CacheSection({super.key});

  @override
  State<CacheSection> createState() => _CacheSectionState();
}

class _CacheSectionState extends State<CacheSection>
    with WidgetsBindingObserver {
  int _artCacheSizeBytes = 0;
  int _streamCacheSizeBytes = 0;
  bool _isLoading = true;
  final YtmCacheManager _ytmCacheManager = YtmCacheManager();

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
    final streamSize = await _ytmCacheManager.getCacheSizeBytes();
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.photo_size_select_actual_rounded,
                color: p.accent, size: 22),
          ),
          title: Text(
            'Artwork Cache',
            style: TextStyle(
                color: p.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14.5),
          ),
          subtitle: Text(
            _isLoading
                ? 'Calculating…'
                : '${_formatSize(_artCacheSizeBytes)} used of $maxMb MB max',
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
          trailing: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: p.error,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Clear'),
            onPressed: () async {
              await manager.clearAllCache();
              await _refreshCacheSize();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Artwork cache cleared successfully')),
                );
              }
            },
          ),
        ),
        Divider(height: 1, color: p.hairline),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cloud_download_rounded,
                color: Colors.redAccent, size: 22),
          ),
          title: Text(
            'YouTube Stream Disk Cache',
            style: TextStyle(
                color: p.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14.5),
          ),
          subtitle: Text(
            _isLoading
                ? 'Calculating…'
                : '${_formatSize(_streamCacheSizeBytes)} cached for zero-latency replay',
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
          trailing: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: p.error,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Clear'),
            onPressed: () async {
              await _ytmCacheManager.clearCache();
              await _refreshCacheSize();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Stream cache cleared successfully')),
                );
              }
            },
          ),
        ),
        Divider(height: 1, color: p.hairline),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: p.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(Icons.disc_full_rounded, color: p.textSecondary, size: 22),
          ),
          title: Text(
            'Maximum Artwork Cache Limit',
            style: TextStyle(
                color: p.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14.5),
          ),
          subtitle: Text(
            '$maxMb MB • Auto-evicts oldest artworks when full',
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
          trailing: Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: p.textTertiary),
          onTap: () => _showMaxCacheLimitPicker(context, manager),
        ),
      ],
    );
  }

  void _showMaxCacheLimitPicker(
      BuildContext context, ArtworkCacheManager manager) {
    final p = context.palette;
    final options = [50, 100, 250, 500];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Maximum Cache Size',
                style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16),
              ),
              const SizedBox(height: 12),
              for (final mb in options)
                ListTile(
                  leading: Icon(
                    manager.maxCacheSizeMb == mb
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: manager.maxCacheSizeMb == mb
                        ? p.accent
                        : p.textTertiary,
                  ),
                  title: Text(
                    '$mb MB',
                    style: TextStyle(
                      color: manager.maxCacheSizeMb == mb
                          ? p.accent
                          : p.textPrimary,
                      fontWeight: manager.maxCacheSizeMb == mb
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    await manager.setMaxCacheSizeMb(mb);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
