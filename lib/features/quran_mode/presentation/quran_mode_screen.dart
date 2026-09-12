// lib/features/quran_mode/presentation/quran_mode_screen.dart
import 'package:flutter/material.dart';

import '../../../core/theme/aura_theme.dart';
import '../../player/presentation/widgets/quran_mode_sheet.dart';

/// Full-screen Quran Mode surface. The interactive controls live in the shared
/// [QuranModePanel] so the sheet and this screen never drift apart.
class QuranModeScreen extends StatelessWidget {
  const QuranModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: const Text('Quran Mode',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.only(top: 4, bottom: 32),
        child: QuranModePanel(),
      ),
    );
  }
}
