import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class ScrobbleStatsScreen extends StatefulWidget {
  const ScrobbleStatsScreen({super.key});

  @override
  State<ScrobbleStatsScreen> createState() => _ScrobbleStatsScreenState();
}

class _ScrobbleStatsScreenState extends State<ScrobbleStatsScreen> {
  int _lastScrobbleTime = 0;
  int _totalScrobbles = 0;
  List<int> _last7DaysScrobbles = [0, 0, 0, 0, 0, 0, 0];
  List<String> _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  List<MapEntry<String, int>> _topArtists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    final lastTime = prefs.getInt('last_scrobble_time') ?? 0;
    final total = prefs.getInt('total_scrobble_count') ?? 0;

    // Load top artists from music repository play counts
    final repo = getIt<IMusicRepository>();
    final songsRes = await repo.getAllSongs();
    final allSongs = songsRes.fold((l) => <SongsTableData>[], (r) => r);

    final artistCounts = <String, int>{};
    for (final song in allSongs) {
      final count = song.playCount;
      if (count > 0 && song.artist.isNotEmpty && song.artist != 'Unknown') {
        artistCounts[song.artist] =
            (artistCounts[song.artist] ?? 0) + count.toInt();
      }
    }
    final sortedArtists = artistCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Real 7-day distribution from scrobble_daily_log
    Map<String, dynamic> dailyLog = {};
    final rawDaily = prefs.getString('scrobble_daily_log');
    if (rawDaily != null && rawDaily.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawDaily);
        if (decoded is Map) {
          dailyLog = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    const weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return (dailyLog[key] as int?) ?? 0;
    });

    final labels = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return weekdayLetters[d.weekday - 1];
    });

    if (mounted) {
      setState(() {
        _lastScrobbleTime = lastTime;
        _totalScrobbles = total;
        _last7DaysScrobbles = days;
        _dayLabels = labels;
        _topArtists = sortedArtists.take(5).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lastDateStr = _lastScrobbleTime > 0
        ? DateTime.fromMillisecondsSinceEpoch(_lastScrobbleTime)
            .toLocal()
            .toString()
            .split('.')
            .first
        : context.l10n.settingsNeverLabel;

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          backgroundColor: p.surface,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: Text(context.l10n.scrobblingAnalytics,
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: p.accent))
          : ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, 120),
              children: [
                // Overview Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s18),
                  decoration: BoxDecoration(
                    color: p.surfaceCard,
                    borderRadius: BorderRadius.circular(AppRadii.r20),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.sync_alt_rounded, color: p.primary),
                          const SizedBox(width: AppSpacing.s10),
                          Text(context.l10n.universalScrobblingEngine,
                            style: TextStyle(
                              fontSize: AppFontSize.bodyLarge,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(context.l10n.scrobblingServicesDesc,
                        style: TextStyle(fontSize: AppFontSize.bodySmall, color: p.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Divider(color: p.hairline),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(context.l10n.totalScrobbles,
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: AppFontSize.bodySmall)),
                          Text('$_totalScrobbles',
                              style: TextStyle(
                                  color: p.accent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(context.l10n.lastScrobbled,
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: AppFontSize.bodySmall)),
                          Text(lastDateStr,
                              style: TextStyle(
                                  color: p.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.bodySmall)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),

                // 7-Day Activity Chart Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s18),
                  decoration: BoxDecoration(
                    color: p.surfaceCard,
                    borderRadius: BorderRadius.circular(AppRadii.r20),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bar_chart_rounded,
                              color: p.accent, size: 20),
                          const SizedBox(width: AppSpacing.xs),
                          Text(context.l10n.last7DaysActivity,
                            style: TextStyle(
                                fontSize: AppFontSize.callout,
                                fontWeight: FontWeight.w700,
                                color: p.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s20),
                      SizedBox(
                        height: 130,
                        child: CustomPaint(
                          size: const Size(double.infinity, 130),
                          painter: _ScrobbleBarChartPainter(
                            data: _last7DaysScrobbles,
                            labels: _dayLabels,
                            barColor: p.primary,
                            labelColor: p.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),

                // Top Artists
                if (_topArtists.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s18),
                    decoration: BoxDecoration(
                      color: p.surfaceCard,
                      borderRadius: BorderRadius.circular(AppRadii.r20),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.leaderboard_rounded,
                                color: p.primary, size: 20),
                            const SizedBox(width: AppSpacing.xs),
                            Text(context.l10n.topScrobbledArtists,
                              style: TextStyle(
                                  fontSize: AppFontSize.callout,
                                  fontWeight: FontWeight.w700,
                                  color: p.textPrimary),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (int i = 0; i < _topArtists.length; i++) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
                            child: Row(
                              children: [
                                Text(
                                  '#${i + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: i == 0 ? p.accent : p.textSecondary,
                                    fontSize: AppFontSize.bodySmall,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    _topArtists[i].key,
                                    style: TextStyle(
                                        color: p.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: AppFontSize.bodySmall),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  context.l10n.settingsPlaysCount(_topArtists[i].value),
                                  style: TextStyle(
                                      color: p.textSecondary, fontSize: AppFontSize.label),
                                ),
                              ],
                            ),
                          ),
                          if (i < _topArtists.length - 1)
                            Divider(color: p.hairline, height: 8),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
      ),
    );
  }
}

class _ScrobbleBarChartPainter extends CustomPainter {
  final List<int> data;
  final List<String> labels;
  final Color barColor;
  final Color labelColor;

  const _ScrobbleBarChartPainter({
    required this.data,
    required this.labels,
    required this.barColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxVal = data.fold<int>(1, math.max);
    final barWidth = (size.width / (data.length * 2)).clamp(12.0, 32.0);
    final spacing = (size.width - (barWidth * data.length)) / (data.length + 1);

    final paint = Paint()
      ..color = barColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final val = data[i];
      final heightRatio = val / maxVal;
      final barHeight = (size.height - 30) * heightRatio;
      final x = spacing + i * (barWidth + spacing);
      final y = (size.height - 24) - barHeight;

      final rRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight.clamp(4.0, size.height)),
        const Radius.circular(AppRadii.r6),
      );
      canvas.drawRRect(rRect, paint);

      final textSpan = TextSpan(
        text: i < labels.length ? labels[i] : '',
        style: TextStyle(
            color: labelColor, fontSize: AppFontSize.caption, fontWeight: FontWeight.w600),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(x + (barWidth - textPainter.width) / 2, size.height - 18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScrobbleBarChartPainter oldDelegate) => true;
}
