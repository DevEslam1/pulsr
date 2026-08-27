// lib/features/player/presentation/themes/custom_theme_builder_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../settings/cubit/settings_cubit.dart';

class CustomThemeBuilderScreen extends StatefulWidget {
  const CustomThemeBuilderScreen({super.key});

  @override
  State<CustomThemeBuilderScreen> createState() => _CustomThemeBuilderScreenState();
}

class _CustomThemeBuilderScreenState extends State<CustomThemeBuilderScreen> {
  int _accentColor = 0xFF9B9EF5;
  double _cornerRadius = 24.0;
  bool _glowEnabled = true;

  static const List<int> _paletteOptions = [
    0xFF9B9EF5, // Lavender
    0xFF00E5FF, // Cyan
    0xFFFF2A6D, // Neon Pink
    0xFF05FFA1, // Neon Green
    0xFFFFD700, // Gold
    0xFFFF6B4A, // Coral Sunset
    0xFFB388FF, // Deep Violet
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.surface,
        elevation: 0,
        title: Text(
          'Custom Theme Studio',
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          // Live Theme Preview Card
          Container(
            height: 220,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF14172B),
              borderRadius: BorderRadius.circular(_cornerRadius),
              border: Border.all(color: Color(_accentColor).withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                if (_glowEnabled)
                  BoxShadow(
                    color: Color(_accentColor).withValues(alpha: 0.25),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Color(_accentColor).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(_cornerRadius / 2),
                      ),
                      child: Icon(Icons.music_note_rounded, color: Color(_accentColor), size: 32),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Live Theme Preview',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pulsr Audiophile Edition',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                LinearProgressIndicator(
                  value: 0.65,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(_accentColor)),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
                    const SizedBox(width: 24),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Color(_accentColor),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 28),
                    ),
                    const SizedBox(width: 24),
                    Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Accent Color Palette',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: p.textPrimary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _paletteOptions.map((colorVal) {
              final isSelected = _accentColor == colorVal;
              return GestureDetector(
                onTap: () {
                  setState(() => _accentColor = colorVal);
                  context.read<SettingsCubit>().setCustomAccentColor(Color(colorVal));
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(colorVal),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded, color: Colors.black, size: 22)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          Text(
            'Card & Artwork Corner Radius (${_cornerRadius.round()}px)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: p.textPrimary),
          ),
          Slider(
            value: _cornerRadius,
            min: 0.0,
            max: 48.0,
            activeColor: Color(_accentColor),
            onChanged: (val) => setState(() => _cornerRadius = val),
          ),
          const SizedBox(height: 16),

          SwitchListTile(
            title: Text('Ambient Acoustic Glow', style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text('Glows with the active track artwork', style: TextStyle(color: p.textSecondary, fontSize: 12)),
            value: _glowEnabled,
            activeThumbColor: Color(_accentColor),
            onChanged: (val) => setState(() => _glowEnabled = val),
          ),
        ],
      ),
    );
  }
}
