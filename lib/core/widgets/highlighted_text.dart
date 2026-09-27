// lib/core/widgets/highlighted_text.dart
import 'package:flutter/material.dart';

/// A widget that renders [text] with substring occurrences of [query] highlighted
/// using [matchStyle], while un-matched text retains [baseStyle].
class PulsrHighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle baseStyle;
  final TextStyle matchStyle;
  final int? maxLines;
  final TextOverflow overflow;

  const PulsrHighlightedText({
    super.key,
    required this.text,
    required this.query,
    required this.baseStyle,
    required this.matchStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final spans = <TextSpan>[];
    int start = 0;
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        }
        break;
      }
      if (index > start) {
        spans.add(
            TextSpan(text: text.substring(start, index), style: baseStyle));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: matchStyle,
      ));
      start = index + query.length;
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
