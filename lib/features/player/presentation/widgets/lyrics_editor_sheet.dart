// lib/features/player/presentation/widgets/lyrics_editor_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../../cubit/player_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/error_logger.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class LyricsEditorSheet extends StatefulWidget {
  final SongsTableData song;
  final Duration currentPosition;
  final List<LyricsLine> initialLyrics;
  final ValueChanged<List<LyricsLine>> onSave;

  const LyricsEditorSheet({
    super.key,
    required this.song,
    required this.currentPosition,
    required this.initialLyrics,
    required this.onSave,
  });

  @override
  State<LyricsEditorSheet> createState() => _LyricsEditorSheetState();
}

class _LyricsEditorSheetState extends State<LyricsEditorSheet> {
  late List<LyricsLine> _lines;
  // Stable per-row widget keys. Keying rows by their list index desynced the
  // text fields after a deletion (row i+1's editing state moved to key i while
  // its `initialValue` was only read on first build). Keys travel with their
  // line through add/delete/sort so the displayed text always matches `_lines`.
  late List<Key> _rowKeys;
  // Live playback position. The sheet used to stamp `widget.currentPosition`,
  // captured when it opened, so every "stamp" and the "Now at" header were
  // frozen at open time while playback kept running underneath.
  final ValueNotifier<Duration> _livePosition = ValueNotifier(Duration.zero);
  StreamSubscription<Duration>? _positionSub;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _livePosition.value = widget.currentPosition;
    _lines = List.from(widget.initialLyrics);
    if (_lines.isEmpty) {
      _lines = [
        LyricsLine(
            timestamp: const Duration(seconds: 0), text: 'First lyric line...'),
      ];
    }
    _rowKeys = List.generate(_lines.length, (_) => UniqueKey());
    try {
      final cubit = context.read<PlayerCubit>();
      _positionSub = cubit.rawPositionStream.listen((pos) {
        _livePosition.value = pos;
      });
    } catch (_) {
      try {
        if (getIt.isRegistered<PlayerCubit>()) {
          final cubit = getIt<PlayerCubit>();
          _positionSub = cubit.rawPositionStream.listen((pos) {
            _livePosition.value = pos;
          });
        }
      } catch (e, st) {
        ErrorLogger.log('PlayerCubit unavailable for lyrics editor position stream',
            error: e, stackTrace: st, category: 'LyricsEditor');
      }
    }
    if (_positionSub == null) {
      _fallbackTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        bool isPlaying = true;
        try {
          isPlaying = context.read<PlayerCubit>().state.isPlaying;
        } catch (_) {
          try {
            if (getIt.isRegistered<PlayerCubit>()) {
              isPlaying = getIt<PlayerCubit>().state.isPlaying;
            }
          } catch (_) {}
        }
        if (isPlaying) {
          _livePosition.value = _livePosition.value + const Duration(milliseconds: 250);
        }
      });
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _fallbackTimer?.cancel();
    _livePosition.dispose();
    super.dispose();
  }

  void _stampCurrentPosition(int index) {
    if (index < 0 || index >= _lines.length) return;
    final stamp = _livePosition.value;
    setState(() {
      final old = _lines[index];
      _lines[index] =
          LyricsLine(timestamp: stamp, text: old.text);
    });
  }

  void _adjustOffset(int index, int deltaMs) {
    if (index < 0 || index >= _lines.length) return;
    setState(() {
      final old = _lines[index];
      final newMs =
          (old.timestamp.inMilliseconds + deltaMs).clamp(0, 3600000);
      _lines[index] =
          LyricsLine(timestamp: Duration(milliseconds: newMs), text: old.text);
    });
  }

  void _addNewLine() {
    setState(() {
      _lines.add(
          LyricsLine(timestamp: _livePosition.value, text: 'New line...'));
      _rowKeys.add(UniqueKey());
    });
  }

  void _deleteLine(int index) {
    setState(() {
      if (_lines.length > 1) {
        _lines.removeAt(index);
        _rowKeys.removeAt(index);
      }
    });
  }

  void _sortLines() {
    setState(() {
      final pairs = List.generate(
          _lines.length, (i) => (_lines[i], _rowKeys[i]));
      pairs.sort((a, b) => a.$1.timestamp.compareTo(b.$1.timestamp));
      _lines = [for (final p in pairs) p.$1];
      _rowKeys = [for (final p in pairs) p.$2];
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.lg),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(AppRadii.r2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.lyricsEditorTitle,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: AppFontSize.title,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(context.l10n.nowAtLabel,
                    style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  ValueListenableBuilder<Duration>(
                    valueListenable: _livePosition,
                    builder: (context, pos, _) => Text(
                      Formatters.formatDuration(pos),
                      style: TextStyle(
                          color: p.primary,
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.sort_rounded, color: p.primary),
                    onPressed: _sortLines,
                    tooltip: context.l10n.dspSortByTime,
                  ),
                  IconButton(
                    icon: Icon(Icons.add_rounded, color: p.primary),
                    onPressed: _addNewLine,
                    tooltip: context.l10n.dspAddLine,
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.r12)),
                    ),
                    onPressed: () {
                      final sorted = List<LyricsLine>.from(_lines)
                        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
                      widget.onSave(sorted);
                      Navigator.pop(context);
                    },
                    child: Text(context.l10n.save,
                        style: TextStyle(
                            color: p.onAccent, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s14),
          Expanded(
            child: ListView.separated(
              itemCount: _lines.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) {
                final line = _lines[index];
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: p.surfaceCard,
                    borderRadius: BorderRadius.circular(AppRadii.r14),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      // Tap-to-play preview button
                      IconButton(
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        color: p.primary,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget,
                        ),
                        onPressed: () {
                          try {
                            final cubit = context.read<PlayerCubit>();
                            cubit.seek(line.timestamp);
                          } catch (_) {
                            getIt<PlayerCubit>().seek(line.timestamp);
                          }
                        },
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      // Timestamp stamp button
                      InkWell(
                        onTap: () => _stampCurrentPosition(index),
                        borderRadius: BorderRadius.circular(AppRadii.r8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: AppSpacing.minTouchTarget,
                            minWidth: AppSpacing.minTouchTarget,
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs, vertical: AppSpacing.s6),
                            decoration: BoxDecoration(
                              color: p.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppRadii.r8),
                            ),
                            child: Text(
                              Formatters.formatDuration(line.timestamp),
                              style: TextStyle(
                                color: p.primary,
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s10),
                      // Text input field
                        Expanded(
                          child: TextFormField(
                            // Stable per-row key so deleting a row cannot make
                            // the wrong line's editing state render here.
                            key: _rowKeys[index],
                          initialValue: line.text,
                          style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.bodySmall),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) {
                            _lines[index] = LyricsLine(
                                timestamp: line.timestamp, text: val);
                          },
                        ),
                      ),
                      // Offset adjust buttons
                      IconButton(
                        icon: const Icon(Icons.remove_rounded, size: 16),
                        color: p.textSecondary,
                        onPressed: () => _adjustOffset(index, -250),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_rounded, size: 16),
                        color: p.textSecondary,
                        onPressed: () => _adjustOffset(index, 250),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        color: p.textSecondary,
                        onPressed: () => _deleteLine(index),
                        tooltip: context.l10n.dspDeleteLine,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
