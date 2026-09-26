// lib/features/settings/presentation/widgets/love_dedication_card.dart
import 'package:flutter/material.dart';

class LoveDedicationCard extends StatefulWidget {
  const LoveDedicationCard({super.key});

  @override
  State<LoveDedicationCard> createState() => _LoveDedicationCardState();
}

class _LoveDedicationCardState extends State<LoveDedicationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  int _loveClicks = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.94, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _showLoveLetterDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _LoveLetterSheet(
        onHeartSent: () {
          setState(() => _loveClicks++);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF380D26), // Rich wine
              Color(0xFF1E0716), // Dark berry
              Color(0xFF12030D), // Deep obsidian rose
            ],
          ),
          border: Border.all(
            color: const Color(0xFFFF2A85).withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF2A85).withValues(alpha: 0.18),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Ambient background glow circles
              Positioned(
                top: -30,
                right: -20,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF2A85).withValues(alpha: 0.16),
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                left: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF7BB0).withValues(alpha: 0.12),
                  ),
                ),
              ),

              // Card Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top tag & Animated Heart
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF2A85).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFF2A85).withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '✨ SPECIAL DEDICATION',
                                style: TextStyle(
                                  color: Color(0xFFFF7BB0),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFF2A85).withValues(alpha: 0.22),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF2A85).withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFFFF2A85),
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Main Title
                    const Text(
                      'For Dr. Basbosa ❤️',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Love Message
                    const Text(
                      'Every note, beat, and melody in this app was tuned with endless love just for you. You bring harmony to my world.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: Color(0xFFF3D5E4),
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Bottom Row: Signature + Interactive Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Signature
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Forever Yours,',
                              style: TextStyle(
                                fontSize: 11,
                                color: const Color(0xFFF3D5E4).withValues(alpha: 0.75),
                                fontWeight: FontWeight.w600,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Eng. Eslam ✨',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFF85BC),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),

                        // Action Button
                        InkWell(
                          onTap: () => _showLoveLetterDialog(context),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF2A85), Color(0xFFE01E6F)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF2A85).withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.favorite,
                                  size: 15,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _loveClicks > 0
                                      ? 'Loved x$_loveClicks'
                                      : 'Open Letter 💌',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoveLetterSheet extends StatefulWidget {
  final VoidCallback onHeartSent;
  const _LoveLetterSheet({required this.onHeartSent});

  @override
  State<_LoveLetterSheet> createState() => _LoveLetterSheetState();
}

class _LoveLetterSheetState extends State<_LoveLetterSheet> {
  int _sentHearts = 0;

  void _sendHeart() {
    widget.onHeartSent();
    setState(() {
      _sentHearts++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1B0716),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Color(0xFFFF2A85), width: 1.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Handle bar
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),

              // Cute Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF2A85).withValues(alpha: 0.18),
                  border: Border.all(
                    color: const Color(0xFFFF2A85).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFFF2A85),
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                'A Message for Dr. Basbosa ❤️',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF280C20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFF2A85).withValues(alpha: 0.2),
                  ),
                ),
                child: const Text(
                  'To the most wonderful Dr. Basbosa,\n\n'
                  'Music sounds so much sweeter with you in my life. '
                  'This app was customized piece by piece with care, love, and passion '
                  'so you can enjoy your favorite tracks in style.\n\n'
                  'You are my greatest melody and forever my favorite person in the entire universe. 🌸✨',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Color(0xFFF6D8E8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                '— With all my love, Eng. Eslam 💖',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF85BC),
                ),
              ),
              const SizedBox(height: 14),

              // Tap to send love button
              ElevatedButton.icon(
                onPressed: _sendHeart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF2A85),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.favorite, size: 16),
                label: Text(
                  _sentHearts > 0
                      ? 'Sent $_sentHearts Love Moments 💕'
                      : 'Tap to Send Love 💕',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
