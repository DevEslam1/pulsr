import 'package:pulsr/core/widgets/pulsr_key_value.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'dart:convert';
import 'package:intl/intl.dart' show DateFormat;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
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
  DateTime _chartDate = DateTime.now();
  List<MapEntry<String, int>> _topArtists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastTime = prefs.getInt('last_scrobble_time') ?? 0;
      final total = prefs.getInt('total_scrobble_count') ?? 0;

      // Load top artists from music repository play counts
      List<SongsTableData> allSongs = [];
      try {
        if (getIt.isRegistered<IMusicRepository>()) {
          final repo = getIt<IMusicRepository>();
          final songsRes = await repo.getAllSongs();
          allSongs = songsRes.fold((l) => <SongsTableData>[], (r) => r);
        }
      } catch (e, st) {
        ErrorLogger.log(
          'Failed to load songs for scrobble stats',
          error: e,
          stackTrace: st,
          category: 'ScrobbleStats',
        );
      }

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

      final now = DateTime.now();
      final days = List.generate(7, (i) {
        final d = now.subtract(Duration(days: 6 - i));
        final key =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        return (dailyLog[key] as int?) ?? 0;
      });

      if (mounted) {
        setState(() {
          _lastScrobbleTime = lastTime;
          _totalScrobbles = total;
          _last7DaysScrobbles = days;
          _chartDate = now;
          _topArtists = sortedArtists.take(5).toList();
          _isLoading = false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to load scrobble stats',
        error: e,
        stackTrace: st,
        category: 'ScrobbleStats',
      );
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final material = MaterialLocalizations.of(context);
    final date =
        DateTime.fromMillisecondsSinceEpoch(_lastScrobbleTime).toLocal();
    final lastDateStr = _lastScrobbleTime > 0
        ? '${material.formatShortDate(date)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}'
        : context.l10n.settingsNeverLabel;
    final dayLabels = List.generate(
        7,
        (i) => DateFormat.E(Localizations.localeOf(context).toString())
            .format(_chartDate.subtract(Duration(days: 6 - i))));

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          backgroundColor: p.surface,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: Text(
            context.l10n.scrobblingAnalytics,
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: _isLoading
                ? SkeletonShimmer(
                    child: ListView(
                      padding: EdgeInsetsDirectional.fromSTEB(
                          AppSpacing.s20,
                          AppSpacing.sm,
                          AppSpacing.s20,
                          PulsrLayoutMetrics.scrollBottom(context)),
                      children: const [
                        SkeletonBox(height: 132, radius: AppRadii.r20),
                        SizedBox(height: AppSpacing.s20),
                        SkeletonBox(height: 206, radius: AppRadii.r20),
                        SizedBox(height: AppSpacing.s20),
                        SkeletonBox(height: 188, radius: AppRadii.r20),
                      ],
                    ),
                  )
                : ListView(
                    padding: EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.s20,
                        AppSpacing.sm,
                        AppSpacing.s20,
                        PulsrLayoutMetrics.scrollBottom(context)),
                    children: [
                      // Overview Card
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.s18),
                        decoration: BoxDecoration(
                          color: p.surfaceCard,
                          borderRadius: AppRadii.r20All,
                          border: Border.all(color: p.hairline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.sync_alt_rounded, color: p.primary),
                                const SizedBox(width: AppSpacing.s10),
                                Expanded(
                                    child: Text(
                                  context.l10n.universalScrobblingEngine,
                                  style: TextStyle(
                                    fontSize: AppFontSize.bodyLarge,
                                    fontWeight: FontWeight.w700,
                                    color: p.textPrimary,
                                  ),
                                )),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              context.l10n.scrobblingServicesDesc,
                              style: TextStyle(
                                  fontSize: AppFontSize.bodySmall,
                                  color: p.textSecondary),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Divider(color: p.hairline),
                            const SizedBox(height: AppSpacing.sm),
                            PulsrKeyValue(
                                label: Text(context.l10n.totalScrobbles,
                                    style: TextStyle(
                                        color: p.textSecondary,
                                        fontSize: AppFontSize.bodySmall)),
                                value: Text('$_totalScrobbles',
                                    style: TextStyle(
                                        color: p.accent,
                                        fontWeight: FontWeight.w700,
                                        fontSize: AppFontSize.body))),
                            const SizedBox(height: AppSpacing.xs),
                            PulsrKeyValue(
                                label: Text(context.l10n.lastScrobbled,
                                    style: TextStyle(
                                        color: p.textSecondary,
                                        fontSize: AppFontSize.bodySmall)),
                                value: Text(lastDateStr,
                                    style: TextStyle(
                                        color: p.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: AppFontSize.bodySmall))),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s20),

                      // 7-Day Activity Chart Card
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.s18),
                        decoration: BoxDecoration(
                          color: p.surfaceCard,
                          borderRadius: AppRadii.r20All,
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
                                Expanded(
                                    child: Text(
                                  context.l10n.last7DaysActivity,
                                  style: TextStyle(
                                      fontSize: AppFontSize.callout,
                                      fontWeight: FontWeight.w700,
                                      color: p.textPrimary),
                                )),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s20),
                            SizedBox(
                              height: 130,
                              child: Semantics(
                                label:
                                    '${context.l10n.last7DaysActivity}: ${List.generate(7, (i) => '${dayLabels[i]} ${_last7DaysScrobbles[i]}').join(', ')}',
                                child: CustomPaint(
                                  size: const Size(double.infinity, 130),
                                  painter: _ScrobbleBarChartPainter(
                                    data: _last7DaysScrobbles,
                                    labels: dayLabels,
                                    barColor: p.primary,
                                    labelColor: p.textSecondary,
                                    textDirection: Directionality.of(context),
                                    textScaler:
                                        MediaQuery.textScalerOf(context),
                                  ),
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
                            borderRadius: AppRadii.r20All,
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
                                  Expanded(
                                      child: Text(
                                    context.l10n.topScrobbledArtists,
                                    style: TextStyle(
                                        fontSize: AppFontSize.callout,
                                        fontWeight: FontWeight.w700,
                                        color: p.textPrimary),
                                  )),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              for (int i = 0; i < _topArtists.length; i++) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.s6),
                                  child: Row(
                                    children: [
                                      Text(
                                        '#${i + 1}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: i == 0
                                              ? p.accent
                                              : p.textSecondary,
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
                                        context.l10n.settingsPlaysCount(
                                            _topArtists[i].value),
                                        style: TextStyle(
                                            color: p.textSecondary,
                                            fontSize: AppFontSize.label),
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
        ),
      ),
    );
  }
}

@visibleForTesting
class ScrobbleBarChartPainter extends CustomPainter {
  final List<int> data;
  final List<String> labels;
  final Color barColor;
  final Color labelColor;
  final TextDirection textDirection;
  final TextScaler textScaler;

  const ScrobbleBarChartPainter({
    required this.data,
    required this.labels,
    required this.barColor,
    required this.labelColor,
    this.textDirection = TextDirection.ltr,
    this.textScaler = TextScaler.noScaling,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width <= 0 || size.height <= 0) return;
    final maxVal = math.max(data.fold<int>(1, math.max), 1);
    final availableWidth = size.width;
    final double barWidth;
    final double spacing;

    if (data.length == 1) {
      barWidth = math.min(32.0, availableWidth * 0.4).clamp(4.0, 32.0);
      spacing = math.max(0.0, (availableWidth - barWidth) / 2);
    } else {
      barWidth = (availableWidth / (data.length * 2)).clamp(4.0, 32.0);
      spacing = math.max(
          0.0, (availableWidth - (barWidth * data.length)) / (data.length + 1));
    }

    final paint = Paint()
      ..color = barColor
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
        ellipsis: '…');
    final labelHeight = textScaler.scale(AppFontSize.caption) + 10;
    final usableHeight = math.max(10.0, size.height - labelHeight - 6);

    for (int i = 0; i < data.length; i++) {
      final val = data[i];
      final heightRatio = (val / maxVal).clamp(0.0, 1.0);
      final barHeight = usableHeight * heightRatio;
      final slot = textDirection == TextDirection.rtl ? data.length - 1 - i : i;
      final x = spacing + slot * (barWidth + spacing);
      final y = size.height - labelHeight - barHeight;

      final rRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight.clamp(4.0, size.height)),
        const Radius.circular(AppRadii.r6),
      );
      canvas.drawRRect(rRect, paint);

      if (i < labels.length && labels[i].isNotEmpty) {
        textPainter.text = TextSpan(
          text: labels[i],
          style: TextStyle(
              color: labelColor,
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w600),
        );
        textPainter.layout(maxWidth: availableWidth / data.length);
        textPainter.paint(
          canvas,
          Offset(x + (barWidth - textPainter.width) / 2,
              size.height - labelHeight + 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ScrobbleBarChartPainter oldDelegate) {
    return oldDelegate.barColor != barColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler ||
        !listEquals(oldDelegate.data, data) ||
        !listEquals(oldDelegate.labels, labels);
  }
}

typedef _ScrobbleBarChartPainter = ScrobbleBarChartPainter;
