// lib/core/utils/love_feedback.dart
import 'package:flutter/material.dart';

void showFavoriteFeedback(BuildContext context, bool isFavorite) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isFavorite
                  ? 'Added to Favorites ❤️\nDr. Basbosa, you are my #1 favorite person forever! 🌸✨'
                  : 'Removed from Favorites (You are still my favorite person ❤️)',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFFF2A85),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

void showNowPlayingLoveMessage(BuildContext context, {String? songTitle}) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _NowPlayingLoveSheet(songTitle: songTitle),
  );
}

class _NowPlayingLoveSheet extends StatefulWidget {
  final String? songTitle;
  const _NowPlayingLoveSheet({this.songTitle});

  @override
  State<_NowPlayingLoveSheet> createState() => _NowPlayingLoveSheetState();
}

class _NowPlayingLoveSheetState extends State<_NowPlayingLoveSheet> {
  int _loveTaps = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C0516),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Color(0xFFFF2A85), width: 1.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Glowing Heart
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF2A85).withValues(alpha: 0.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF2A85).withValues(alpha: 0.4),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFFF2A85),
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),

              // Title
              const Text(
                'Dedicated to Dr. Basbosa 💕',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),

              // Message container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B0920),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFF2A85).withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  children: [
                    if (widget.songTitle != null && widget.songTitle!.isNotEmpty) ...[
                      Text(
                        '🎶 Playing: "${widget.songTitle}"',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFF85BC),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const Text(
                      '"Every track in this player is tuned with my whole heart for you. '
                      'Whenever music plays, remember that you are my absolute favorite person and my forever love." 🌸✨',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: Color(0xFFF7D9E9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Signature
              const Text(
                '— Forever Yours, Eng. Eslam 💖',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF85BC),
                ),
              ),
              const SizedBox(height: 16),

              // Love reaction button
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _loveTaps++);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF2A85),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.favorite, size: 16),
                label: Text(
                  _loveTaps > 0
                      ? 'Sent $_loveTaps Love Moments 💕'
                      : 'Send Love Back 💕',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
