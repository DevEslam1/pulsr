// lib/features/player/presentation/widgets/quran_mode_button.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/player_cubit.dart';
import 'quran_mode_sheet.dart';

/// Bottom-dock toggle for Quran Mode, styled to sit beside the existing
/// equalizer / output / speed actions. Mirrors the private `_DockIconButton`
/// that every player theme defines locally.
class QuranModeDockButton extends StatelessWidget {
  final Color activeColor;
  final Color inactiveColor;
  final bool isTablet;

  const QuranModeDockButton({
    super.key,
    required this.activeColor,
    required this.inactiveColor,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    final isActive =
        context.select<PlayerCubit, bool>((c) => c.state.isQuranModeEnabled);

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        QuranModeSheet.show(context);
      },
      borderRadius: BorderRadius.circular(20),
      child: Tooltip(
        message: isActive ? 'Quran Mode: On' : 'Quran Mode: Off',
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.all(isTablet ? 8 : 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? activeColor.withValues(alpha: 0.22)
                      : Colors.transparent,
                  border: isActive
                      ? Border.all(
                          color: activeColor.withValues(alpha: 0.45),
                          width: 1.2,
                        )
                      : null,
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  size: isTablet ? 22 : 20,
                  color: isActive ? activeColor : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
