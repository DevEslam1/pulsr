// lib/features/library/presentation/widgets/genre_hierarchy_view.dart
import 'dart:collection';
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../domain/models/genre_item.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class GenreCategory {
  final String name;
  final IconData icon;
  final List<String> keywords;

  // B-28: LinkedHashMap guarantees deterministic insertion-order eviction for keys.first
  static final LinkedHashMap<String, RegExp> _regexCache = LinkedHashMap<String, RegExp>();
  static const int _maxCacheSize = 100;

  static RegExp _keywordRegex(String kw) {
    final cached = _regexCache[kw];
    if (cached != null) return cached;
    if (_regexCache.length >= _maxCacheSize) {
      _regexCache.remove(_regexCache.keys.first);
    }
    final regex = RegExp('\\b${RegExp.escape(kw)}\\b', caseSensitive: false);
    _regexCache[kw] = regex;
    return regex;
  }

  // FIX-H15: Static method to clear regex cache for memory cleanup and tests
  static void clearCache() {
    _regexCache.clear();
  }

  const GenreCategory(this.name, this.icon, this.keywords);

  bool matches(String genreName) {
    for (final kw in keywords) {
      if (_keywordRegex(kw).hasMatch(genreName)) return true;
    }
    return false;
  }
}

class GenreHierarchyView extends StatefulWidget {
  final List<GenreItem> genres;

  const GenreHierarchyView({super.key, required this.genres});

  @override
  State<GenreHierarchyView> createState() => _GenreHierarchyViewState();
}

class _GenreHierarchyViewState extends State<GenreHierarchyView> {
  static int _instanceCount = 0;

  @override
  void initState() {
    super.initState();
    _instanceCount++;
  }

  @override
  void dispose() {
    _instanceCount--;
    if (_instanceCount <= 0) {
      _instanceCount = 0;
      GenreCategory.clearCache();
    }
    super.dispose();
  }

  List<GenreCategory> _categories(BuildContext context) => [
    GenreCategory(context.l10n.browseGenreRockMetal, Icons.electric_bolt_rounded,
        ['rock', 'metal', 'grunge', 'punk', 'alternative', 'روك', 'ميتال']),
    GenreCategory(context.l10n.browseGenreElectronicDance, Icons.album_rounded, [
      'electronic',
      'techno',
      'house',
      'edm',
      'ambient',
      'trance',
      'synth',
      'إلكترونك',
      'هاوس',
      'تكنو'
    ]),
    GenreCategory(context.l10n.browseGenreHipHopRnb, Icons.mic_external_on_rounded, [
      'hip hop',
      'hip-hop',
      'rap',
      'r&b',
      'trap',
      'soul',
      'راب',
      'هيب هوب',
      'تراب',
      'مهرجانات'
    ]),
    GenreCategory(context.l10n.browseGenreJazzBlues, Icons.music_note_rounded,
        ['jazz', 'blues', 'swing', 'bebop', 'جاز', 'بلوز']),
    GenreCategory(context.l10n.browseGenreClassicalInstrumental, Icons.piano_rounded, [
      'classical',
      'instrumental',
      'soundtrack',
      'orchestral',
      'score',
      'كلاسيك',
      'موسيقى كلاسيكية',
      'أوركسترا',
      'موسيقى تصويرية'
    ]),
    GenreCategory(context.l10n.browseGenrePopAcoustic, Icons.star_rounded, [
      'pop',
      'acoustic',
      'indie',
      'folk',
      'vocal',
      'بوب',
      'شعبي',
      'أكوستيك',
      'فولك'
    ]),
    GenreCategory(context.l10n.browseGenreArabicRegional, Icons.queue_music_rounded, [
      'طرب',
      'عربي',
      'خليجي',
      'مغربي',
      'شامي',
      'مصري',
      'أندلسي',
      'موشحات',
      'arabic',
      'tarab',
      'khaleeji',
      'oriental',
      'middle eastern'
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final categories = _categories(context);

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 120),
      children: [
        for (final category in categories) ...[
          _buildCategoryGroup(context, category, p),
          const SizedBox(height: AppSpacing.sm),
        ],
        // Remaining uncategorized genres
        _buildUncategorizedGroup(context, categories, p),
      ],
    );
  }

  Widget _buildCategoryGroup(
      BuildContext context, GenreCategory cat, PulsrPalette p) {
    final matching = widget.genres.where((g) => cat.matches(g.name)).toList();

    if (matching.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadii.r18),
        border: Border.all(color: p.hairline),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(cat.icon, color: p.primary, size: 20),
        ),
        title: Text(
          cat.name,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: AppFontSize.callout,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${matching.length} ${context.l10n.browseSubGenres} • ${matching.fold<int>(0, (sum, g) => sum + g.songCount)} ${context.l10n.songs}',
          style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
        ),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: matching.map((g) {
                return Semantics(
                  button: true,
                  label: '${g.name}, ${g.songCount} ${context.l10n.songs}',
                  child: ActionChip(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    backgroundColor: p.surfaceContainer,
                    side: BorderSide(color: p.hairline),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.r12)),
                    label: Text(
                      '${g.name} (${g.songCount})',
                      style: TextStyle(
                          fontSize: AppFontSize.label,
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                    onPressed: () =>
                        context.push('/genre', extra: g),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUncategorizedGroup(BuildContext context, List<GenreCategory> categories, PulsrPalette p) {
    final uncategorized = widget.genres.where((g) {
      final name = g.name;
      return !categories.any((cat) => cat.matches(name));
    }).toList();

    if (uncategorized.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadii.r18),
        border: Border.all(color: p.hairline),
      ),
      child: ExpansionTile(
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.category_rounded, color: p.accent, size: 20),
        ),
        title: Text(context.l10n.otherGenres,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: AppFontSize.callout,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${uncategorized.length} ${context.l10n.genres}',
          style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
        ),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: uncategorized.map((g) {
                return Semantics(
                  button: true,
                  label: '${g.name}, ${g.songCount} ${context.l10n.songs}',
                  child: ActionChip(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    backgroundColor: p.surfaceContainer,
                    side: BorderSide(color: p.hairline),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.r12)),
                    label: Text(
                      '${g.name} (${g.songCount})',
                      style: TextStyle(
                          fontSize: AppFontSize.label,
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                    onPressed: () =>
                        context.push('/genre', extra: g),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
