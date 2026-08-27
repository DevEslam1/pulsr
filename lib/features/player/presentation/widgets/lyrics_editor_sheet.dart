// lib/features/player/presentation/widgets/lyrics_editor_sheet.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/lyrics_line.dart';

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

  @override
  void initState() {
    super.initState();
    _lines = List.from(widget.initialLyrics);
    if (_lines.isEmpty) {
      _lines = [
        LyricsLine(timestamp: const Duration(seconds: 0), text: 'First lyric line...'),
      ];
    }
  }

  void _stampCurrentPosition(int index) {
    setState(() {
      final old = _lines[index];
      _lines[index] = LyricsLine(timestamp: widget.currentPosition, text: old.text);
    });
  }

  void _adjustOffset(int index, int deltaMs) {
    setState(() {
      final old = _lines[index];
      final newMs = (old.timestamp.inMilliseconds + deltaMs).clamp(0, 3600000);
      _lines[index] = LyricsLine(timestamp: Duration(milliseconds: newMs), text: old.text);
    });
  }

  void _addNewLine() {
    setState(() {
      _lines.add(LyricsLine(timestamp: widget.currentPosition, text: 'New line...'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Synced Lyrics Editor',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Now at: ${Formatters.formatDuration(widget.currentPosition)}',
                    style: TextStyle(color: p.primary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.add_rounded, color: p.primary),
                    onPressed: _addNewLine,
                    tooltip: 'Add Line',
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      widget.onSave(_lines);
                      Navigator.pop(context);
                    },
                    child: const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              itemCount: _lines.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final line = _lines[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surfaceCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      // Timestamp stamp button
                      InkWell(
                        onTap: () => _stampCurrentPosition(index),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: p.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            Formatters.formatDuration(line.timestamp),
                            style: TextStyle(
                              color: p.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Text input field
                      Expanded(
                        child: TextFormField(
                          initialValue: line.text,
                          style: TextStyle(color: p.textPrimary, fontSize: 13),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) {
                            _lines[index] = LyricsLine(timestamp: line.timestamp, text: val);
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
