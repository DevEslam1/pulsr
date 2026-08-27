// lib/features/library/presentation/widgets/genre_hierarchy_view.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../domain/models/genre_item.dart';

class GenreCategory {
  final String name;
  final IconData icon;
  final List<String> keywords;

  const GenreCategory(this.name, this.icon, this.keywords);
}

class GenreHierarchyView extends StatelessWidget {
  final List<GenreItem> genres;

  const GenreHierarchyView({super.key, required this.genres});

  static const List<GenreCategory> _categories = [
    GenreCategory('Rock & Metal', Icons.electric_bolt_rounded, ['rock', 'metal', 'grunge', 'punk', 'alternative', 'روك', 'ميتال']),
    GenreCategory('Electronic & Dance', Icons.album_rounded, ['electronic', 'techno', 'house', 'edm', 'ambient', 'trance', 'synth', 'إلكترونك', 'هاوس', 'تكنو']),
    GenreCategory('Hip-Hop & R&B', Icons.mic_external_on_rounded, ['hip hop', 'hip-hop', 'rap', 'r&b', 'trap', 'soul', 'راب', 'هيب هوب', 'تراب', 'مهرجانات']),
    GenreCategory('Jazz & Blues', Icons.music_note_rounded, ['jazz', 'blues', 'swing', 'bebop', 'جاز', 'بلوز']),
    GenreCategory('Classical & Instrumental', Icons.piano_rounded, ['classical', 'instrumental', 'soundtrack', 'orchestral', 'score', 'كلاسيك', 'موسيقى كلاسيكية', 'أوركسترا', 'موسيقى تصويرية']),
    GenreCategory('Pop & Acoustic', Icons.star_rounded, ['pop', 'acoustic', 'indie', 'folk', 'vocal', 'بوب', 'شعبي', 'أكوستيك', 'فولك']),
    GenreCategory('Arabic & Regional', Icons.queue_music_rounded, ['طرب', 'عربي', 'خليجي', 'مغربي', 'شامي', 'مصري', 'أندلسي', 'موشحات', 'arabic', 'tarab', 'khaleeji', 'oriental', 'middle eastern']),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        for (final category in _categories) ...[
          _buildCategoryGroup(context, category, p),
          const SizedBox(height: 12),
        ],
        // Remaining uncategorized genres
        _buildUncategorizedGroup(context, p),
      ],
    );
  }

  Widget _buildCategoryGroup(BuildContext context, GenreCategory cat, PulsrPalette p) {
    final matching = genres.where((g) {
      final name = g.name.toLowerCase();
      return cat.keywords.any((kw) => name.contains(kw));
    }).toList();

    if (matching.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(8),
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
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${matching.length} sub-genres • ${matching.fold<int>(0, (sum, g) => sum + g.songCount)} songs',
          style: TextStyle(color: p.textSecondary, fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: matching.map((g) {
                return ActionChip(
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  label: Text(
                    '${g.name} (${g.songCount})',
                    style: TextStyle(fontSize: 12, color: p.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => context.push('/genre/${Uri.encodeComponent(g.name)}'),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUncategorizedGroup(BuildContext context, PulsrPalette p) {
    final uncategorized = genres.where((g) {
      final name = g.name.toLowerCase();
      return !_categories.any((cat) => cat.keywords.any((kw) => name.contains(kw)));
    }).toList();

    if (uncategorized.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
      ),
      child: ExpansionTile(
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.category_rounded, color: p.accent, size: 20),
        ),
        title: Text(
          'Other Genres',
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${uncategorized.length} genres',
          style: TextStyle(color: p.textSecondary, fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: uncategorized.map((g) {
                return ActionChip(
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  label: Text(
                    '${g.name} (${g.songCount})',
                    style: TextStyle(fontSize: 12, color: p.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => context.push('/genre/${Uri.encodeComponent(g.name)}'),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
