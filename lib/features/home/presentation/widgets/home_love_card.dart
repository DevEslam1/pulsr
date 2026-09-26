// lib/features/home/presentation/widgets/home_love_card.dart
import 'package:flutter/material.dart';

class HomeLoveCard extends StatefulWidget {
  const HomeLoveCard({super.key});

  @override
  State<HomeLoveCard> createState() => _HomeLoveCardState();
}

class _HomeLoveCardState extends State<HomeLoveCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  bool _loved = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onTapHeart() {
    setState(() => _loved = !_loved);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Eng. Eslam loves Dr. Basbosa to the moon & stars! 💖✨',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFF2A85),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF340B22), // Wine glow
            Color(0xFF1F0617), // Deep dark berry
            Color(0xFF13030E), // Obsidian rose
          ],
        ),
        border: Border.all(
          color: const Color(0xFFFF2A85).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF2A85).withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _onTapHeart,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Beating Heart Icon
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF2A85).withValues(alpha: 0.22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF2A85).withValues(alpha: 0.45),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      _loved ? Icons.favorite_rounded : Icons.favorite_rounded,
                      color: const Color(0xFFFF2A85),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Text message
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Special Melody for You',
                            style: TextStyle(
                              color: Color(0xFFFF7BB0),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF2A85).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Dr. Basbosa 💕',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        '"You make every beat worthwhile. Enjoy your music, my love!"',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '— Eng. Eslam ✨',
                        style: TextStyle(
                          color: Color(0xFFFF94C2),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
