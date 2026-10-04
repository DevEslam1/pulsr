// lib/features/shell/presentation/widgets/player_shortcut_scope.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import 'shortcut_help_sheet.dart';

/// Global keyboard shortcuts for desktop/tablet.
///
/// Bindings:
///   Space        → play/pause
///   → / ←        → seek forward / backward 10s
///   ↑ / ↓        → volume up / down 5%
///   N / P        → next / previous
///   F            → toggle favorite (if provided)
///   M            → mute toggle
///   L            → toggle lyrics
///   Q            → toggle queue
///   Shift + / (?) → show keyboard shortcut help sheet
///
/// Shortcuts are suppressed while a text input ([EditableText]) has focus so
/// typing in a search field never triggers playback actions.
/// Each shortcut triggers lightweight visual feedback via [PulsrToast].
class PlayerShortcutScope extends StatelessWidget {
  final Widget child;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onSeekForward;
  final VoidCallback onSeekBackward;
  final VoidCallback onVolumeUp;
  final VoidCallback onVolumeDown;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleLyrics;
  final VoidCallback onToggleQueue;
  final VoidCallback? onToggleFavorite;

  const PlayerShortcutScope({
    super.key,
    required this.child,
    required this.onTogglePlayPause,
    required this.onSeekForward,
    required this.onSeekBackward,
    required this.onVolumeUp,
    required this.onVolumeDown,
    required this.onNext,
    required this.onPrevious,
    required this.onToggleMute,
    required this.onToggleLyrics,
    required this.onToggleQueue,
    this.onToggleFavorite,
  });

  /// True when the primary focus belongs to a text input, in which case
  /// single-letter/space shortcuts must not fire.
  static bool isTextInputFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  VoidCallback _guardWithToast(
    BuildContext context,
    VoidCallback action, {
    required String message,
    required IconData icon,
  }) {
    return () {
      if (isTextInputFocused()) return;
      action();
      PulsrToast.show(
        context,
        message: message,
        icon: icon,
        duration: const Duration(milliseconds: 1400),
      );
    };
  }

  VoidCallback _guardHelp(BuildContext context) {
    return () {
      if (isTextInputFocused()) return;
      ShortcutHelpSheet.show(context);
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): _guardWithToast(
        context,
        onTogglePlayPause,
        message: l10n.shortcutPlayPause,
        icon: Icons.play_arrow_rounded,
      ),
      const SingleActivator(LogicalKeyboardKey.arrowRight): _guardWithToast(
        context,
        onSeekForward,
        message: l10n.shortcutSeekForward,
        icon: Icons.forward_10_rounded,
      ),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): _guardWithToast(
        context,
        onSeekBackward,
        message: l10n.shortcutSeekBackward,
        icon: Icons.replay_10_rounded,
      ),
      const SingleActivator(LogicalKeyboardKey.arrowUp): _guardWithToast(
        context,
        onVolumeUp,
        message: l10n.shortcutVolumeUp,
        icon: Icons.volume_up_rounded,
      ),
      const SingleActivator(LogicalKeyboardKey.arrowDown): _guardWithToast(
        context,
        onVolumeDown,
        message: l10n.shortcutVolumeDown,
        icon: Icons.volume_down_rounded,
      ),
      const SingleActivator(LogicalKeyboardKey.keyN): _guardWithToast(
        context,
        onNext,
        message: l10n.shortcutNext,
        icon: Icons.skip_next_rounded,
      ),
      const SingleActivator(LogicalKeyboardKey.keyP): _guardWithToast(
        context,
        onPrevious,
        message: l10n.shortcutPrevious,
        icon: Icons.skip_previous_rounded,
      ),
      const SingleActivator(LogicalKeyboardKey.keyM): _guardWithToast(
        context,
        onToggleMute,
        message: l10n.shortcutMute,
        icon: Icons.volume_off_rounded,
      ),
      const SingleActivator(LogicalKeyboardKey.keyL): _guardWithToast(
        context,
        onToggleLyrics,
        message: l10n.shortcutLyrics,
        icon: Icons.lyrics_rounded,
      ),
      const SingleActivator(LogicalKeyboardKey.keyQ): _guardWithToast(
        context,
        onToggleQueue,
        message: l10n.shortcutQueue,
        icon: Icons.queue_music_rounded,
      ),
      const SingleActivator(LogicalKeyboardKey.slash, shift: true):
          _guardHelp(context),
    };

    if (onToggleFavorite != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.keyF)] =
          _guardWithToast(
        context,
        onToggleFavorite!,
        message: l10n.shortcutFavorite,
        icon: Icons.favorite_rounded,
      );
    }

    return CallbackShortcuts(
      bindings: bindings,
      // autofocus guarantees a focused descendant exists so key events reach
      // the CallbackShortcuts Focus even when no control has focus.
      child: Focus(autofocus: true, child: child),
    );
  }
}
